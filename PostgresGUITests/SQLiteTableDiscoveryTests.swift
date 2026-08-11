//
//  SQLiteTableDiscoveryTests.swift
//  PostgresGUITests
//
//  Phase 2 completion tests: table discovery, column parsing, primary keys,
//  DDL generation, and view classification at both the executor and service layers.
//  Covers gaps identified in the Phase 2 spec that existing tests miss.
//

import XCTest
import GRDB
@testable import PostgresGUI

// MARK: - Executor-Level Gap Tests

/// Tests for SQLiteQueryExecutor edge cases not covered by SQLiteQueryExecutorTests.
final class SQLiteTableDiscoveryExecutorTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private let executor = SQLiteQueryExecutor()

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE products (
                    category TEXT NOT NULL,
                    sku TEXT NOT NULL,
                    name TEXT,
                    price REAL,
                    PRIMARY KEY (category, sku)
                );
                INSERT INTO products VALUES ('electronics', 'TV-001', 'Television', 499.99);
                INSERT INTO products VALUES ('electronics', 'PH-001', 'Phone', 299.99);

                CREATE TABLE no_columns_pk (val TEXT);

                CREATE VIEW product_summary AS
                SELECT category, COUNT(*) AS cnt, AVG(price) AS avg_price
                FROM products GROUP BY category;

                CREATE TABLE with_defaults (
                    id INTEGER PRIMARY KEY,
                    status TEXT DEFAULT 'active',
                    created TEXT DEFAULT (datetime('now')),
                    count INTEGER DEFAULT 0
                );
            """)
        }
    }

    override func tearDown() async throws {
        dbQueue = nil
    }

    // MARK: - Composite Primary Keys

    func testFetchPrimaryKeysCompositeOrdering() async throws {
        let pks = try await dbQueue.read { db in
            try self.executor.fetchPrimaryKeys(db: db, table: "products")
        }
        // Composite PK columns must be returned in declaration order
        XCTAssertEqual(pks, ["category", "sku"])
    }

    // MARK: - View Classification

    func testFetchTablesClassifiesViewsCorrectly() async throws {
        let tables = try await dbQueue.read { db in
            try self.executor.fetchTables(db: db)
        }
        let view = tables.first { $0.name == "product_summary" }
        XCTAssertNotNil(view, "View 'product_summary' should appear in table list")
        XCTAssertEqual(view?.tableType, .view)

        let table = tables.first { $0.name == "products" }
        XCTAssertNotNil(table)
        XCTAssertEqual(table?.tableType, .regular)
    }

    // MARK: - Column Defaults

    func testFetchColumnsPreservesDefaults() async throws {
        let columns = try await dbQueue.read { db in
            try self.executor.fetchColumns(db: db, table: "with_defaults")
        }

        let statusCol = columns.first { $0.name == "status" }
        XCTAssertEqual(statusCol?.defaultValue, "'active'")

        let countCol = columns.first { $0.name == "count" }
        XCTAssertEqual(countCol?.defaultValue, "0")
    }

    // MARK: - Column Types

    func testFetchColumnsNoTypeDeclaration() async throws {
        // SQLite allows columns with no declared type
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE untyped (a, b, c)")
        }
        let columns = try await dbQueue.read { db in
            try self.executor.fetchColumns(db: db, table: "untyped")
        }
        XCTAssertEqual(columns.count, 3)
        // Columns with no declared type should get "ANY"
        for col in columns {
            XCTAssertEqual(col.dataType, "ANY")
        }
    }

    // MARK: - DDL for Views

    func testGenerateDDLForView() async throws {
        let ddl = try await dbQueue.read { db in
            try self.executor.generateDDL(db: db, table: "product_summary")
        }
        XCTAssertTrue(ddl.contains("CREATE VIEW product_summary"))
        XCTAssertTrue(ddl.hasSuffix(";"))
    }

    // MARK: - Empty Database

    func testFetchTablesOnEmptyDatabase() async throws {
        let emptyDb = try DatabaseQueue()
        let tables = try await emptyDb.read { db in
            try self.executor.fetchTables(db: db)
        }
        XCTAssertTrue(tables.isEmpty)
    }
}

// MARK: - Service-Level Tests

/// Tests for SQLiteDatabaseService — the facade layer that gates on connection state.
/// Uses a real temp file to exercise the full connect → query → disconnect lifecycle.
final class SQLiteTableDiscoveryServiceTests: XCTestCase {
    private var service: SQLiteDatabaseService!
    private var tempFileURL: URL!

    @MainActor
    override func setUp() async throws {
        service = SQLiteDatabaseService()

        // Create a temp SQLite file with test schema
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite")

        let dbQueue = try DatabaseQueue(path: tempFileURL.path)
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE customers (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE
                );
                INSERT INTO customers VALUES (1, 'Alice', 'alice@example.com');
                INSERT INTO customers VALUES (2, 'Bob', 'bob@example.com');

                CREATE TABLE orders (
                    order_id INTEGER PRIMARY KEY,
                    customer_id INTEGER NOT NULL,
                    total REAL NOT NULL DEFAULT 0.0,
                    FOREIGN KEY (customer_id) REFERENCES customers(id)
                );

                CREATE VIEW customer_orders AS
                SELECT c.name, COUNT(o.order_id) AS order_count
                FROM customers c LEFT JOIN orders o ON c.id = o.customer_id
                GROUP BY c.name;
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

    // MARK: - fetchTables (service layer)

    @MainActor
    func testFetchTablesReturnsTablesAndViews() async throws {
        let tables = try await service.fetchTables()
        let names = Set(tables.map(\.name))
        XCTAssertTrue(names.contains("customers"))
        XCTAssertTrue(names.contains("orders"))
        XCTAssertTrue(names.contains("customer_orders"))
    }

    @MainActor
    func testFetchTablesViewTypeClassification() async throws {
        let tables = try await service.fetchTables()
        let view = tables.first { $0.name == "customer_orders" }
        XCTAssertEqual(view?.tableType, .view)
    }

    // MARK: - fetchColumnInfo (service layer)

    @MainActor
    func testFetchColumnInfoReturnsAllColumns() async throws {
        let columns = try await service.fetchColumnInfo(table: "customers")
        XCTAssertEqual(columns.count, 3)
        let names = columns.map(\.name)
        XCTAssertEqual(names, ["id", "name", "email"])
    }

    @MainActor
    func testFetchColumnInfoNullability() async throws {
        let columns = try await service.fetchColumnInfo(table: "customers")
        let nameCol = columns.first { $0.name == "name" }
        XCTAssertEqual(nameCol?.isNullable, false, "'name' is NOT NULL")

        let emailCol = columns.first { $0.name == "email" }
        XCTAssertEqual(emailCol?.isNullable, true, "'email' allows NULL")
    }

    @MainActor
    func testFetchColumnInfoDataTypes() async throws {
        let columns = try await service.fetchColumnInfo(table: "orders")
        let totalCol = columns.first { $0.name == "total" }
        XCTAssertEqual(totalCol?.dataType, "REAL")

        let idCol = columns.first { $0.name == "order_id" }
        XCTAssertEqual(idCol?.dataType, "INTEGER")
        XCTAssertTrue(idCol?.isPrimaryKey ?? false)
    }

    @MainActor
    func testFetchColumnInfoDefault() async throws {
        let columns = try await service.fetchColumnInfo(table: "orders")
        let totalCol = columns.first { $0.name == "total" }
        XCTAssertEqual(totalCol?.defaultValue, "0.0")
    }

    // MARK: - fetchPrimaryKeys (service layer)

    @MainActor
    func testFetchPrimaryKeysSingleColumn() async throws {
        let pks = try await service.fetchPrimaryKeys(table: "customers")
        XCTAssertEqual(pks, ["id"])
    }

    @MainActor
    func testFetchPrimaryKeysNoPK() async throws {
        // Views have no primary keys
        let pks = try await service.fetchPrimaryKeys(table: "customer_orders")
        XCTAssertTrue(pks.isEmpty)
    }

    // MARK: - generateDDL (service layer)

    @MainActor
    func testGenerateDDLForTable() async throws {
        let ddl = try await service.generateDDL(table: "customers")
        XCTAssertTrue(ddl.contains("CREATE TABLE customers"))
        XCTAssertTrue(ddl.contains("name TEXT NOT NULL"))
        XCTAssertTrue(ddl.hasSuffix(";"))
    }

    @MainActor
    func testGenerateDDLForView() async throws {
        let ddl = try await service.generateDDL(table: "customer_orders")
        XCTAssertTrue(ddl.contains("CREATE VIEW customer_orders"))
    }

    @MainActor
    func testGenerateDDLForMissing() async throws {
        let ddl = try await service.generateDDL(table: "nonexistent")
        XCTAssertTrue(ddl.contains("No DDL found"))
    }

    // MARK: - Not-connected guards

    @MainActor
    func testFetchTablesThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        do {
            _ = try await disconnected.fetchTables()
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    @MainActor
    func testFetchColumnInfoThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        do {
            _ = try await disconnected.fetchColumnInfo(table: "foo")
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    @MainActor
    func testFetchPrimaryKeysThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        do {
            _ = try await disconnected.fetchPrimaryKeys(table: "foo")
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    @MainActor
    func testGenerateDDLThrowsWhenNotConnected() async throws {
        let disconnected = SQLiteDatabaseService()
        do {
            _ = try await disconnected.generateDDL(table: "foo")
            XCTFail("Expected notConnected error")
        } catch let error as FileOpenError {
            XCTAssertEqual(error, .notConnected)
        }
    }
}
