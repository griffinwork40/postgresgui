//
//  SQLiteDataEditingServiceTests.swift
//  PostgresGUITests
//
//  Service-level wiring tests for INSERT / UPDATE / DELETE via SQLiteDatabaseService.
//  Uses a real temp file to exercise the full connect → write → verify lifecycle.
//

import XCTest
import GRDB
@testable import PostgresGUI

// MARK: - Service-Level Wiring Tests

final class SQLiteDataEditingServiceTests: XCTestCase {

    private var service: SQLiteDatabaseService!
    private var tempFileURL: URL!

    @MainActor
    override func setUp() async throws {
        service = SQLiteDatabaseService()

        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("edit_test_\(UUID().uuidString).sqlite")

        let dbQueue = try DatabaseQueue(path: tempFileURL.path)
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE employees (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    department TEXT
                );
                INSERT INTO employees VALUES (1, 'Alice', 'Engineering');
                INSERT INTO employees VALUES (2, 'Bob', 'Marketing');
            """)
        }

        try await service.connect(filePath: tempFileURL.path)
    }

    @MainActor
    override func tearDown() async throws {
        await service.disconnect()
        try? FileManager.default.removeItem(at: tempFileURL)
        service = nil
        tempFileURL = nil
    }

    // MARK: - deleteRows

    @MainActor
    func testDeleteRowsViaService() async throws {
        let row = TableRow(values: ["id": "1", "name": "Alice", "department": "Engineering"])
        try await service.deleteRows(
            schema: "main",
            table: "employees",
            primaryKeyColumns: ["id"],
            rows: [row]
        )

        let (rows, _) = try await service.executeQuery("SELECT * FROM employees")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].values["name"], "Bob")
    }

    @MainActor
    func testDeleteRowsThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        let row = TableRow(values: ["id": "1"])
        do {
            try await disconnected.deleteRows(
                schema: "main",
                table: "employees",
                primaryKeyColumns: ["id"],
                rows: [row]
            )
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    // MARK: - updateRow

    @MainActor
    func testUpdateRowViaService() async throws {
        let original = TableRow(values: ["id": "2", "name": "Bob", "department": "Marketing"])
        let updated: [String: RowEditValue] = ["department": .value("Sales")]

        try await service.updateRow(
            schema: "main",
            table: "employees",
            primaryKeyColumns: ["id"],
            originalRow: original,
            updatedValues: updated
        )

        let (rows, _) = try await service.executeQuery(
            "SELECT department FROM employees WHERE id = 2"
        )
        XCTAssertEqual(rows.first?.values["department"], "Sales")
    }

    @MainActor
    func testUpdateNonexistentRowThrows() async throws {
        let ghost = TableRow(values: ["id": "999", "name": "Ghost", "department": nil])
        let updated: [String: RowEditValue] = ["name": .value("Nobody")]

        do {
            try await service.updateRow(
                schema: "main",
                table: "employees",
                primaryKeyColumns: ["id"],
                originalRow: ghost,
                updatedValues: updated
            )
            XCTFail("Expected error for non-existent row update")
        } catch let error as FileOpenError {
            if case .unknownError(let msg) = error {
                XCTAssertTrue(msg.contains("No rows were updated"))
            } else {
                XCTFail("Expected .unknownError, got \(error)")
            }
        }
    }

    @MainActor
    func testUpdateRowThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        let row = TableRow(values: ["id": "1", "name": "Alice"])
        do {
            try await disconnected.updateRow(
                schema: "main",
                table: "employees",
                primaryKeyColumns: ["id"],
                originalRow: row,
                updatedValues: ["name": .value("New")]
            )
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    // MARK: - insertRow

    @MainActor
    func testInsertRowViaService() async throws {
        let values: [String: RowEditValue] = [
            "id": .value("42"),
            "name": .value("Carol"),
            "department": .value("Engineering")
        ]
        try await service.insertRow(table: "employees", values: values)

        let (rows, _) = try await service.executeQuery(
            "SELECT * FROM employees WHERE id = 42"
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.values["name"], "Carol")
    }

    @MainActor
    func testInsertRowThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        do {
            try await disconnected.insertRow(
                table: "employees",
                values: ["name": .value("Ghost")]
            )
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    // MARK: - Read-only rejection

    @MainActor
    func testReadOnlyDatabaseRejectsWrite() async throws {
        let readOnlyService = SQLiteDatabaseService()
        try await readOnlyService.connect(filePath: tempFileURL.path, readOnly: true)
        defer { Task { await readOnlyService.disconnect() } }

        let row = TableRow(values: ["id": "1"])
        do {
            try await readOnlyService.deleteRows(
                schema: "main",
                table: "employees",
                primaryKeyColumns: ["id"],
                rows: [row]
            )
            XCTFail("Expected error for read-only database write attempt")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
