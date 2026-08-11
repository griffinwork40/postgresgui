//
//  SQLiteConnectionManager.swift
//  PostgresGUI
//
//  Actor-isolated manager for SQLite database connections via GRDB.
//  Uses one DatabaseQueue per opened file for predictable connection-scoped
//  behavior (PRAGMAs, ATTACH, TEMP objects, transactions share one connection).
//

import Foundation
import GRDB
import Logging

actor SQLiteConnectionManager {

    // MARK: - Properties

    private var dbQueue: DatabaseQueue?
    private var currentFilePath: String?
    private var isReadOnlyMode: Bool = false
    private let logger = Logger.debugLogger(label: "com.sqlitegui.connection")

    /// Generation counter to detect stale operations.
    private var connectionGeneration: UInt64 = 0

    var isConnected: Bool {
        dbQueue != nil
    }

    // MARK: - Connection Management

    /// Open a SQLite database file.
    /// Does NOT automatically execute any PRAGMAs — the database is opened as-is.
    func connect(filePath: String, readOnly: Bool = false) async throws {
        logger.info("Opening SQLite database: \(filePath), readOnly: \(readOnly)")

        connectionGeneration &+= 1
        let myGeneration = connectionGeneration

        // Close existing connection if any
        if dbQueue != nil {
            await disconnect()
        }

        // Validate file exists (unless we're creating a new one)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            throw FileOpenError.fileNotFound(filePath)
        }

        guard fileManager.isReadableFile(atPath: filePath) else {
            throw FileOpenError.permissionDenied(filePath)
        }

        if !readOnly && !fileManager.isWritableFile(atPath: filePath) {
            logger.info("File is not writable, opening in read-only mode")
        }

        var config = Configuration()
        config.readonly = readOnly
        // Do NOT set any PRAGMAs here — inspect and display existing state,
        // let the user explicitly change settings.

        do {
            let queue = try DatabaseQueue(path: filePath, configuration: config)

            // Verify this is actually a SQLite database by executing a trivial query
            try queue.read { db in
                _ = try Int.fetchOne(db, sql: "SELECT 1")
            }

            guard connectionGeneration == myGeneration else {
                logger.warning("Stale connection detected, discarding")
                return
            }

            self.dbQueue = queue
            self.currentFilePath = filePath
            self.isReadOnlyMode = readOnly
            logger.info("Successfully opened SQLite database")
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw FileOpenError.notADatabase(filePath)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY {
            throw FileOpenError.fileLocked(filePath)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CANTOPEN {
            throw FileOpenError.permissionDenied(filePath)
        } catch {
            logger.error("Failed to open database: \(error)")
            throw FileOpenError.unknownError(error.localizedDescription)
        }
    }

    /// Close the database connection.
    func disconnect() async {
        logger.info("Closing SQLite database")
        // DatabaseQueue.close() is not needed — GRDB handles cleanup on dealloc.
        // Setting to nil releases the queue and closes the underlying sqlite3 handle.
        dbQueue = nil
        currentFilePath = nil
        isReadOnlyMode = false
    }

    /// Full shutdown — same as disconnect for SQLite (no event loops to tear down).
    func shutdown() async {
        await disconnect()
    }

    /// Interrupt in-flight operations for supersession.
    func interruptInFlightOperationForSupersession() async {
        connectionGeneration &+= 1
        if let queue = dbQueue {
            queue.interrupt()
        }
    }

    /// Execute an operation with the active database.
    func withDatabase<T>(_ operation: @Sendable (Database) throws -> T) async throws -> T {
        guard let queue = dbQueue else {
            throw FileOpenError.notConnected
        }
        return try queue.read { db in
            try operation(db)
        }
    }

    /// Execute a write operation with the active database.
    func withDatabaseWrite<T>(_ operation: @Sendable (Database) throws -> T) async throws -> T {
        guard let queue = dbQueue else {
            throw FileOpenError.notConnected
        }
        guard !isReadOnlyMode else {
            throw FileOpenError.unknownError("Database is opened in read-only mode")
        }
        return try queue.write { db in
            try operation(db)
        }
    }

    /// The currently opened file path.
    var openedFilePath: String? {
        currentFilePath
    }
}
