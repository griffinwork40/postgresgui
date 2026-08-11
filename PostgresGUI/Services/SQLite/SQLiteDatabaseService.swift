//
//  SQLiteDatabaseService.swift
//  PostgresGUI
//
//  High-level service facade for SQLite database operations.
//  Bridges between the SQLite service layer (typed results) and the
//  existing app state/UI layer (which still uses TableRow/QueryResult).
//
//  This service owns the connection manager and query executor,
//  and provides both typed and legacy (display) result interfaces.
//

import Foundation
import GRDB
import Logging

@MainActor
class SQLiteDatabaseService {
    private let connectionManager = SQLiteConnectionManager()
    private let queryExecutor = SQLiteQueryExecutor()
    private let logger = Logger.debugLogger(label: "com.sqlitegui.service")

    // MARK: - Connection State

    private var _isConnected: Bool = false
    private var _currentFilePath: String?

    var isConnected: Bool { _isConnected }
    var currentFilePath: String? { _currentFilePath }

    /// The file name of the currently opened database (for display).
    var connectedDatabaseName: String? {
        guard let path = _currentFilePath else { return nil }
        return (path as NSString).lastPathComponent
    }

    // MARK: - Connection Management

    /// Open a SQLite database file.
    func connect(filePath: String, readOnly: Bool = false) async throws {
        logger.info("Opening: \(filePath)")
        _isConnected = false
        _currentFilePath = nil

        try await connectionManager.connect(filePath: filePath, readOnly: readOnly)

        _currentFilePath = filePath
        _isConnected = true
        logger.info("Connected to: \(filePath)")
    }

    /// Close the current database.
    func disconnect() async {
        logger.info("Disconnecting")
        await connectionManager.disconnect()
        _currentFilePath = nil
        _isConnected = false
    }

    /// Full shutdown.
    func shutdown() async {
        await connectionManager.shutdown()
        _currentFilePath = nil
        _isConnected = false
    }

    /// Interrupt in-flight operations.
    func interruptInFlightOperations() async {
        await connectionManager.interruptInFlightOperationForSupersession()
    }

    // MARK: - Table Operations (return domain models)

    /// Fetch tables from the database.
    func fetchTables() async throws -> [TableInfo] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchTables(db: db)
        }
    }

    /// Fetch column info for a table.
    func fetchColumnInfo(table: String) async throws -> [ColumnInfo] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchColumns(db: db, table: table)
        }
    }

    /// Fetch primary key columns for a table.
    func fetchPrimaryKeys(table: String) async throws -> [String] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchPrimaryKeys(db: db, table: table)
        }
    }

    /// Get the DDL for a table.
    func generateDDL(table: String) async throws -> String {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.generateDDL(db: db, table: table)
        }
    }

    // MARK: - Query Execution (Typed Results)

    /// Execute arbitrary SQL and return typed results.
    func executeQueryTyped(_ sql: String) async throws -> TypedQueryResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.executeQuery(db: db, sql: sql)
        }
    }

    /// Fetch a page of table data as typed results.
    func fetchTableDataTyped(
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> TypedQueryResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchTableData(db: db, table: table, limit: limit, offset: offset)
        }
    }

    // MARK: - Legacy Display Interface (for existing UI compatibility)

    /// Execute SQL and return legacy display types for existing UI code.
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        let typed = try await executeQueryTyped(sql)
        if let error = typed.error { throw error }
        return (typed.toDisplayRows(), typed.columnNames)
    }

    /// Fetch table data as legacy display types.
    func fetchTableData(
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        let typed = try await fetchTableDataTyped(table: table, limit: limit, offset: offset)
        if let error = typed.error { throw error }
        return typed.toDisplayRows()
    }
}
