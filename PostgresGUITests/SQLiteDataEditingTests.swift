//
//  SQLiteDataEditingTests.swift
//  PostgresGUITests
//
//  Core executor-level tests for SQLiteRowOperations (UPDATE / DELETE / INSERT)
//  using in-memory GRDB databases. Edge-case table-type tests are in
//  SQLiteDataEditingEdgeCaseTests.swift; service-level tests are in
//  SQLiteDataEditingServiceTests.swift.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class SQLiteDataEditingTests: XCTestCase {

    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT,
                    score REAL DEFAULT 0.0
                );
                INSERT INTO users VALUES (1, 'Alice', 'alice@test.com', 95.5);
                INSERT INTO users VALUES (2, 'Bob', NULL, 82.3);
                INSERT INTO users VALUES (3, 'Charlie', 'charlie@test.com', 0.0);

                CREATE TABLE products (
                    category TEXT NOT NULL,
                    sku TEXT NOT NULL,
                    price REAL,
                    PRIMARY KEY (category, sku)
                );
                INSERT INTO products VALUES ('electronics', 'TV-001', 499.99);
                INSERT INTO products VALUES ('electronics', 'PH-001', 299.99);

                CREATE TABLE items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    label TEXT NOT NULL
                );
            """)
        }
    }

    override func tearDown() async throws {
        dbQueue = nil
    }

    // MARK: - UPDATE

    func testUpdateRowSinglePK() async throws {
        let originalRow = TableRow(values: [
            "id": "1", "name": "Alice", "email": "alice@test.com", "score": "95.5"
        ])
        let updated: [String: RowEditValue] = ["name": .value("Alicia"), "score": .value("99.0")]

        try await dbQueue.write { db in
            let count = try SQLiteRowOperations.updateRow(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                originalRow: originalRow,
                updatedValues: updated
            )
            XCTAssertEqual(count, 1)
        }

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT * FROM users WHERE id = 1")
        }
        XCTAssertEqual(row?["name"] as String?, "Alicia")
        XCTAssertEqual(row?["score"] as Double?, 99.0)
    }

    func testUpdateRowSetNull() async throws {
        let originalRow = TableRow(values: [
            "id": "1", "name": "Alice", "email": "alice@test.com", "score": "95.5"
        ])
        let updated: [String: RowEditValue] = ["email": .null]

        try await dbQueue.write { db in
            _ = try SQLiteRowOperations.updateRow(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                originalRow: originalRow,
                updatedValues: updated
            )
        }

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT email FROM users WHERE id = 1")
        }
        guard let r = row else { XCTFail("Row not found"); return }
        let emailValue: DatabaseValue = r["email"]
        XCTAssertTrue(emailValue.isNull, "email should be NULL after update")
    }

    func testUpdateRowCompositePK() async throws {
        let originalRow = TableRow(values: [
            "category": "electronics", "sku": "TV-001", "price": "499.99"
        ])
        let updated: [String: RowEditValue] = ["price": .value("399.99")]

        try await dbQueue.write { db in
            let count = try SQLiteRowOperations.updateRow(
                db: db,
                table: "products",
                primaryKeyColumns: ["category", "sku"],
                originalRow: originalRow,
                updatedValues: updated
            )
            XCTAssertEqual(count, 1)
        }

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql:
                "SELECT price FROM products WHERE category = 'electronics' AND sku = 'TV-001'"
            )
        }
        XCTAssertEqual(row?["price"] as Double?, 399.99)
    }

    func testUpdateNonexistentRowReturnsZero() async throws {
        let originalRow = TableRow(values: [
            "id": "999", "name": "Ghost", "email": nil, "score": "0.0"
        ])
        let updated: [String: RowEditValue] = ["name": .value("Nobody")]

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.updateRow(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                originalRow: originalRow,
                updatedValues: updated
            )
        }
        XCTAssertEqual(count, 0)
    }

    func testUpdateEmptyUpdatedValues() async throws {
        let originalRow = TableRow(values: ["id": "1", "name": "Alice"])

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.updateRow(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                originalRow: originalRow,
                updatedValues: [:]
            )
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - DELETE

    func testDeleteSingleRow() async throws {
        let row = TableRow(values: ["id": "1", "name": "Alice"])

        let affected = try await dbQueue.write { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                rows: [row]
            )
        }
        XCTAssertEqual(affected, 1)

        let remaining = try await dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users")!
        }
        XCTAssertEqual(remaining, 2)
    }

    func testDeleteMultipleRows() async throws {
        let row1 = TableRow(values: ["id": "1"])
        let row2 = TableRow(values: ["id": "3"])

        let affected = try await dbQueue.write { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                rows: [row1, row2]
            )
        }
        XCTAssertEqual(affected, 2)

        let remaining = try await dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users")!
        }
        XCTAssertEqual(remaining, 1)
    }

    func testDeleteFromEmptyResultSet() async throws {
        let row = TableRow(values: ["id": "999"])

        let affected = try await dbQueue.write { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                rows: [row]
            )
        }
        XCTAssertEqual(affected, 0)
    }

    func testDeleteEmptyRowsArray() async throws {
        let affected = try await dbQueue.write { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: "users",
                primaryKeyColumns: ["id"],
                rows: []
            )
        }
        XCTAssertEqual(affected, 0)

        let remaining = try await dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users")!
        }
        XCTAssertEqual(remaining, 3, "No rows should have been deleted")
    }

    // MARK: - INSERT

    func testInsertRow() async throws {
        let values: [String: RowEditValue] = [
            "id": .value("10"),
            "name": .value("Dave"),
            "email": .value("dave@test.com"),
            "score": .value("77.0")
        ]

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.insertRow(db: db, table: "users", values: values)
        }
        XCTAssertEqual(count, 1)

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT * FROM users WHERE id = 10")
        }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?["name"] as String?, "Dave")
        XCTAssertEqual(row?["score"] as Double?, 77.0)
    }

    func testInsertRowWithNulls() async throws {
        let values: [String: RowEditValue] = [
            "id": .value("20"),
            "name": .value("Eve"),
            "email": .null,
            "score": .null
        ]

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.insertRow(db: db, table: "users", values: values)
        }
        XCTAssertEqual(count, 1)

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT * FROM users WHERE id = 20")
        }
        guard let r = row else { XCTFail("Row not found"); return }
        let emailVal: DatabaseValue = r["email"]
        XCTAssertTrue(emailVal.isNull, "email should be NULL")
    }

    func testInsertRowAutoIncrement() async throws {
        let values: [String: RowEditValue] = ["label": .value("Widget")]

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.insertRow(db: db, table: "items", values: values)
        }
        XCTAssertEqual(count, 1)

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT * FROM items WHERE label = 'Widget'")
        }
        XCTAssertNotNil(row)
        let assignedId = row?["id"] as Int64?
        XCTAssertNotNil(assignedId, "AUTOINCREMENT id should be assigned")
    }
}
