//
//  SQLiteQueryExecutorTests.swift
//  PostgresGUITests
//
//  Tests for SQLiteQueryExecutor using in-memory GRDB databases.
//  Verifies typed value preservation, table discovery, and column metadata.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class SQLiteQueryExecutorTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private let executor = SQLiteQueryExecutor()

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT,
                    score REAL DEFAULT 0.0,
                    data BLOB,
                    active INTEGER NOT NULL DEFAULT 1
                );
                INSERT INTO users (id, name, email, score, active)
                VALUES (1, 'Alice', 'alice@test.com', 95.5, 1);
                INSERT INTO users (id, name, email, score, active)
                VALUES (2, 'Bob', NULL, 82.3, 0);
                INSERT INTO users (id, name, email, score, data, active)
                VALUES (3, 'Charlie', 'charlie@test.com', 0.0, X'DEADBEEF', 1);

                CREATE TABLE orders (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER REFERENCES users(id),
                    amount REAL NOT NULL,
                    created_at TEXT DEFAULT (datetime('now'))
                );
                INSERT INTO orders (user_id, amount) VALUES (1, 29.99);
                INSERT INTO orders (user_id, amount) VALUES (1, 49.99);
                INSERT INTO orders (user_id, amount) VALUES (2, 9.99);

                CREATE VIEW active_users AS
                SELECT id, name, email FROM users WHERE active = 1;

                CREATE INDEX idx_users_email ON users(email);

                CREATE TABLE strict_types (
                    id INTEGER PRIMARY KEY,
                    count INTEGER,
                    ratio REAL,
                    label TEXT,
                    payload BLOB
                ) STRICT;
            """)
        }
    }

    override func tearDown() async throws {
        dbQueue = nil
    }

    // MARK: - Table Discovery

    func testFetchTablesFindsUserTables() throws {
        let tables = try dbQueue.read { db in
            try executor.fetchTables(db: db)
        }

        let names = tables.map(\.name).sorted()
        XCTAssertTrue(names.contains("users"))
        XCTAssertTrue(names.contains("orders"))
        XCTAssertTrue(names.contains("strict_types"))
        // Should include the view
        XCTAssertTrue(names.contains("active_users"))
    }

    func testFetchTablesExcludesSQLiteInternals() throws {
        let tables = try dbQueue.read { db in
            try executor.fetchTables(db: db)
        }

        let names = tables.map(\.name)
        XCTAssertFalse(names.contains { $0.hasPrefix("sqlite_") })
    }

    func testFetchTablesSchemaIsMain() throws {
        let tables = try dbQueue.read { db in
            try executor.fetchTables(db: db)
        }

        for table in tables {
            XCTAssertEqual(table.schema, "main")
        }
    }

    // MARK: - Column Metadata

    func testFetchColumnsForUsers() throws {
        let columns = try dbQueue.read { db in
            try executor.fetchColumns(db: db, table: "users")
        }

        XCTAssertEqual(columns.count, 6)

        let idCol = columns.first { $0.name == "id" }
        XCTAssertNotNil(idCol)
        XCTAssertTrue(idCol!.isPrimaryKey)
        XCTAssertEqual(idCol!.dataType, "INTEGER")

        let nameCol = columns.first { $0.name == "name" }
        XCTAssertNotNil(nameCol)
        XCTAssertFalse(nameCol!.isNullable)
        XCTAssertEqual(nameCol!.dataType, "TEXT")

        let emailCol = columns.first { $0.name == "email" }
        XCTAssertNotNil(emailCol)
        XCTAssertTrue(emailCol!.isNullable)

        let scoreCol = columns.first { $0.name == "score" }
        XCTAssertNotNil(scoreCol)
        XCTAssertEqual(scoreCol!.defaultValue, "0.0")
    }

    // MARK: - Primary Keys

    func testFetchPrimaryKeysForUsers() throws {
        let pks = try dbQueue.read { db in
            try executor.fetchPrimaryKeys(db: db, table: "users")
        }
        XCTAssertEqual(pks, ["id"])
    }

    func testFetchPrimaryKeysForTableWithoutExplicitPK() throws {
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE no_pk (a TEXT, b TEXT)")
        }
        let pks = try dbQueue.read { db in
            try executor.fetchPrimaryKeys(db: db, table: "no_pk")
        }
        XCTAssertTrue(pks.isEmpty)
    }

    // MARK: - DDL Generation

    func testGenerateDDL() throws {
        let ddl = try dbQueue.read { db in
            try executor.generateDDL(db: db, table: "users")
        }
        XCTAssertTrue(ddl.hasPrefix("CREATE TABLE users"))
        XCTAssertTrue(ddl.hasSuffix(";"))
        XCTAssertTrue(ddl.contains("name TEXT NOT NULL"))
    }

    func testGenerateDDLForMissingTable() throws {
        let ddl = try dbQueue.read { db in
            try executor.generateDDL(db: db, table: "nonexistent")
        }
        XCTAssertTrue(ddl.contains("No DDL found"))
    }

    // MARK: - Typed Data Fetching

    func testFetchTableDataReturnsTypedValues() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 10, offset: 0)
        }

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.rows.count, 3)

        // Column names should be present and ordered
        XCTAssertEqual(result.columnNames.first, "id")
        XCTAssertTrue(result.columnNames.contains("name"))
        XCTAssertTrue(result.columnNames.contains("email"))

        // First row: Alice (id=1, name="Alice", email="alice@test.com", score=95.5, data=NULL, active=1)
        let alice = result.rows[0]

        // id should be INTEGER
        let idIndex = result.columnNames.firstIndex(of: "id")!
        XCTAssertEqual(alice[idIndex], .integer(1))

        // name should be TEXT
        let nameIndex = result.columnNames.firstIndex(of: "name")!
        XCTAssertEqual(alice[nameIndex], .text("Alice"))

        // score should be REAL
        let scoreIndex = result.columnNames.firstIndex(of: "score")!
        XCTAssertEqual(alice[scoreIndex], .real(95.5))
    }

    func testNullValuesPreserved() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 10, offset: 0)
        }

        // Bob has NULL email and NULL data
        let bob = result.rows[1]
        let emailIndex = result.columnNames.firstIndex(of: "email")!
        XCTAssertEqual(bob[emailIndex], .null)

        let dataIndex = result.columnNames.firstIndex(of: "data")!
        XCTAssertEqual(bob[dataIndex], .null)
    }

    func testBlobValuesPreserved() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 10, offset: 0)
        }

        // Charlie has BLOB data = 0xDEADBEEF
        let charlie = result.rows[2]
        let dataIndex = result.columnNames.firstIndex(of: "data")!
        if case .blob(let data) = charlie[dataIndex] {
            XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        } else {
            XCTFail("Expected BLOB, got \(charlie[dataIndex])")
        }
    }

    // MARK: - Pagination

    func testPaginationLimit() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 2, offset: 0)
        }
        XCTAssertEqual(result.rows.count, 2)
    }

    func testPaginationOffset() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 10, offset: 2)
        }
        XCTAssertEqual(result.rows.count, 1)  // Only Charlie

        let nameIndex = result.columnNames.firstIndex(of: "name")!
        XCTAssertEqual(result.rows[0][nameIndex], .text("Charlie"))
    }

    // MARK: - Arbitrary SQL Execution

    func testExecuteSelectQuery() throws {
        let result = try dbQueue.read { db in
            try executor.executeQuery(db: db, sql: "SELECT name, score FROM users WHERE score > 90")
        }
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.columnNames, ["name", "score"])
        XCTAssertEqual(result.rows[0][0], .text("Alice"))
        XCTAssertEqual(result.rows[0][1], .real(95.5))
    }

    func testExecuteSelectWithDuplicateColumnNames() throws {
        let result = try dbQueue.read { db in
            try executor.executeQuery(
                db: db,
                sql: "SELECT u.id, o.id FROM users u JOIN orders o ON u.id = o.user_id LIMIT 1"
            )
        }
        XCTAssertTrue(result.isSuccess)
        // Both columns should be named "id"
        XCTAssertEqual(result.columnNames, ["id", "id"])
        // Both values should be accessible by position
        XCTAssertEqual(result.rows[0][0], .integer(1))  // users.id
        // orders.id is also an integer
        if case .integer = result.rows[0][1] {
            // OK
        } else {
            XCTFail("Expected INTEGER for orders.id")
        }
    }

    func testExecuteExpressionQuery() throws {
        let result = try dbQueue.read { db in
            try executor.executeQuery(db: db, sql: "SELECT 1 + 1 AS result, typeof(1) AS type")
        }
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.rows[0][0], .integer(2))
        XCTAssertEqual(result.rows[0][1], .text("integer"))
    }

    func testExecuteCountQuery() throws {
        let result = try dbQueue.read { db in
            try executor.executeQuery(db: db, sql: "SELECT COUNT(*) AS cnt FROM users")
        }
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.rows[0][0], .integer(3))
    }

    // MARK: - Display Conversion

    func testToDisplayRowsPreservesAllTypes() throws {
        let result = try dbQueue.read { db in
            try executor.fetchTableData(db: db, table: "users", limit: 1, offset: 2)
        }
        let displayRows = result.toDisplayRows()
        XCTAssertEqual(displayRows.count, 1)

        let charlie = displayRows[0]
        XCTAssertEqual(charlie.values["name"], "Charlie")
        XCTAssertEqual(charlie.values["data"], "[BLOB: 4 bytes]")
    }
}
