//
//  SQLiteConnectionManagerTests.swift
//  PostgresGUITests
//
//  Tests for SQLiteConnectionManager: file opening, error handling, connection lifecycle.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class SQLiteConnectionManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteGUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    /// Create a valid SQLite database file at the given path.
    private func createTestDatabase(name: String = "test.db") throws -> String {
        let path = tempDir.appendingPathComponent(name).path
        // Create via GRDB to ensure it's a valid SQLite file
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);
                INSERT INTO test VALUES (1, 'hello');
            """)
        }
        return path
    }

    // MARK: - Connection Lifecycle

    func testConnectToValidDatabase() async throws {
        let path = try createTestDatabase()
        let manager = SQLiteConnectionManager()

        try await manager.connect(filePath: path)

        let isConnected = await manager.isConnected
        XCTAssertTrue(isConnected)
    }

    func testDisconnect() async throws {
        let path = try createTestDatabase()
        let manager = SQLiteConnectionManager()

        try await manager.connect(filePath: path)
        await manager.disconnect()

        let isConnected = await manager.isConnected
        XCTAssertFalse(isConnected)
    }

    func testConnectReplacesExistingConnection() async throws {
        let path1 = try createTestDatabase(name: "db1.sqlite")
        let path2 = try createTestDatabase(name: "db2.sqlite")
        let manager = SQLiteConnectionManager()

        try await manager.connect(filePath: path1)
        try await manager.connect(filePath: path2)

        let isConnected = await manager.isConnected
        XCTAssertTrue(isConnected)
        let currentPath = await manager.openedFilePath
        XCTAssertEqual(currentPath, path2)
    }

    // MARK: - Error Cases

    func testConnectToNonexistentFile() async {
        let manager = SQLiteConnectionManager()
        let fakePath = tempDir.appendingPathComponent("does_not_exist.db").path

        do {
            try await manager.connect(filePath: fakePath)
            XCTFail("Expected FileOpenError.fileNotFound")
        } catch let error as FileOpenError {
            if case .fileNotFound = error {
                // expected
            } else {
                XCTFail("Expected .fileNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testConnectToNonDatabaseFile() async throws {
        let path = tempDir.appendingPathComponent("not_a_db.txt").path
        try "This is not a database".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = SQLiteConnectionManager()

        do {
            try await manager.connect(filePath: path)
            XCTFail("Expected FileOpenError.notADatabase")
        } catch let error as FileOpenError {
            if case .notADatabase = error {
                // expected
            } else if case .unknownError = error {
                // GRDB may report this differently depending on version
            } else {
                XCTFail("Expected .notADatabase or .unknownError, got \(error)")
            }
        } catch {
            // Some GRDB versions throw DatabaseError instead
            // Accept any error for a non-database file
        }
    }

    // MARK: - Database Operations

    func testWithDatabaseExecutesQuery() async throws {
        let path = try createTestDatabase()
        let manager = SQLiteConnectionManager()
        try await manager.connect(filePath: path)

        let result: Int = try await manager.withDatabase { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM test")!
        }

        XCTAssertEqual(result, 1)
    }

    func testWithDatabaseThrowsWhenNotConnected() async {
        let manager = SQLiteConnectionManager()

        do {
            let _: Int = try await manager.withDatabase { db in
                try Int.fetchOne(db, sql: "SELECT 1")!
            }
            XCTFail("Expected FileOpenError.notConnected")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
