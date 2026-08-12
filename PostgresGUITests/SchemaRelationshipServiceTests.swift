//
//  SchemaRelationshipServiceTests.swift
//  PostgresGUITests
//
//  Tests for SchemaRelationshipService using in-memory GRDB databases.
//  Verifies FK detection, empty schemas, self-referencing FKs, and
//  composite / multi-FK scenarios.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class SchemaRelationshipServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Create a DatabaseQueue with GRDB's default config (foreign_keys = ON).
    private func makeDB() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    // MARK: - Basic FK detection

    func testSingleForeignKey() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE users (
                    id   INTEGER PRIMARY KEY,
                    name TEXT NOT NULL
                );
                CREATE TABLE orders (
                    id      INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id)
                );
            """)
        }

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        XCTAssertEqual(relationships.count, 1)
        let rel = try XCTUnwrap(relationships.first)
        XCTAssertEqual(rel.sourceTable,  "orders")
        XCTAssertEqual(rel.sourceColumn, "user_id")
        XCTAssertEqual(rel.targetTable,  "users")
        XCTAssertEqual(rel.targetColumn, "id")
    }

    // MARK: - No foreign keys

    func testNoForeignKeysReturnsEmptyArray() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE alpha (id INTEGER PRIMARY KEY, label TEXT);
                CREATE TABLE beta  (id INTEGER PRIMARY KEY, value INTEGER);
            """)
        }

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        XCTAssertTrue(relationships.isEmpty,
            "Tables with no FOREIGN KEY constraints should produce no relationships")
    }

    func testEmptyDatabaseReturnsEmptyRelationships() async throws {
        let db = try makeDB()

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        XCTAssertTrue(relationships.isEmpty)
    }

    // MARK: - Self-referencing FK

    func testSelfReferencingFK() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE categories (
                    id        INTEGER PRIMARY KEY,
                    name      TEXT NOT NULL,
                    parent_id INTEGER REFERENCES categories(id)
                );
            """)
        }

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        XCTAssertEqual(relationships.count, 1)
        let rel = try XCTUnwrap(relationships.first)
        XCTAssertEqual(rel.sourceTable,  "categories")
        XCTAssertEqual(rel.sourceColumn, "parent_id")
        XCTAssertEqual(rel.targetTable,  "categories",
            "Self-referencing FK must point back to the same table")
        XCTAssertEqual(rel.targetColumn, "id")
    }

    // MARK: - Multiple FKs from one table

    func testMultipleForeignKeysFromOneTable() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE products  (id INTEGER PRIMARY KEY, sku  TEXT);
                CREATE TABLE line_items (
                    id          INTEGER PRIMARY KEY,
                    customer_id INTEGER NOT NULL REFERENCES customers(id),
                    product_id  INTEGER NOT NULL REFERENCES products(id),
                    quantity    INTEGER NOT NULL DEFAULT 1
                );
            """)
        }

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        XCTAssertEqual(relationships.count, 2,
            "line_items has two FK columns so two relationships expected")

        let sourceNames = Set(relationships.map(\.sourceTable))
        XCTAssertEqual(sourceNames, ["line_items"])

        let targets = Set(relationships.map(\.targetTable))
        XCTAssertTrue(targets.contains("customers"))
        XCTAssertTrue(targets.contains("products"))
    }

    // MARK: - Full overview (fetchOverview)

    func testFetchOverviewTablesAndRelationships() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE authors (
                    id   INTEGER PRIMARY KEY,
                    name TEXT NOT NULL
                );
                CREATE TABLE books (
                    id        INTEGER PRIMARY KEY,
                    title     TEXT NOT NULL,
                    author_id INTEGER NOT NULL REFERENCES authors(id)
                );
            """)
        }

        let overview = try await db.read { conn in
            try SchemaRelationshipService.fetchOverview(db: conn)
        }

        XCTAssertEqual(overview.tables.count, 2)
        XCTAssertEqual(overview.relationships.count, 1)

        let tableNames = Set(overview.tables.map(\.name))
        XCTAssertTrue(tableNames.contains("authors"))
        XCTAssertTrue(tableNames.contains("books"))
    }

    // MARK: - Table metadata

    func testFetchTablesPrimaryKeys() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE items (
                    id    INTEGER PRIMARY KEY,
                    label TEXT
                );
            """)
        }

        let tables = try await db.read { conn in
            try SchemaRelationshipService.fetchTables(db: conn)
        }

        XCTAssertEqual(tables.count, 1)
        let table = try XCTUnwrap(tables.first)
        XCTAssertEqual(table.name, "items")
        XCTAssertEqual(table.primaryKeys, ["id"])
        XCTAssertEqual(table.columnCount, 2)
    }

    func testFetchTablesCompositePrimaryKey() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE role_assignments (
                    user_id INTEGER NOT NULL,
                    role_id INTEGER NOT NULL,
                    PRIMARY KEY (user_id, role_id)
                );
            """)
        }

        let tables = try await db.read { conn in
            try SchemaRelationshipService.fetchTables(db: conn)
        }

        let table = try XCTUnwrap(tables.first)
        XCTAssertEqual(Set(table.primaryKeys), Set(["user_id", "role_id"]))
        XCTAssertEqual(table.columnCount, 2)
    }

    func testFetchTablesRowCount() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE widgets (id INTEGER PRIMARY KEY, val TEXT);
                INSERT INTO widgets VALUES (1, 'a');
                INSERT INTO widgets VALUES (2, 'b');
                INSERT INTO widgets VALUES (3, 'c');
            """)
        }

        let tables = try await db.read { conn in
            try SchemaRelationshipService.fetchTables(db: conn)
        }

        let table = try XCTUnwrap(tables.first)
        XCTAssertEqual(table.rowCount, 3)
    }

    // MARK: - SchemaOverview helpers

    func testSchemaOverviewOutboundInbound() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE employees (
                    id    INTEGER PRIMARY KEY,
                    dept_id INTEGER REFERENCES departments(id)
                );
            """)
        }

        let overview = try await db.read { conn in
            try SchemaRelationshipService.fetchOverview(db: conn)
        }

        let dept = try XCTUnwrap(overview.tables.first(where: { $0.name == "departments" }))
        let emp  = try XCTUnwrap(overview.tables.first(where: { $0.name == "employees" }))

        XCTAssertTrue(overview.outbound(from: emp).count == 1)
        XCTAssertTrue(overview.inbound(to: dept).count == 1)
        XCTAssertTrue(overview.outbound(from: dept).isEmpty)
        XCTAssertTrue(overview.inbound(to: emp).isEmpty)
        XCTAssertTrue(overview.hasRelationships(dept))
        XCTAssertTrue(overview.hasRelationships(emp))
    }

    func testSchemaOverviewHasRelationshipsFalseForIsolatedTable() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE standalone (id INTEGER PRIMARY KEY, data TEXT);
            """)
        }

        let overview = try await db.read { conn in
            try SchemaRelationshipService.fetchOverview(db: conn)
        }

        let table = try XCTUnwrap(overview.tables.first)
        XCTAssertFalse(overview.hasRelationships(table))
    }

    // MARK: - FK relationship ID uniqueness

    func testRelationshipIDIsUnique() async throws {
        let db = try makeDB()
        try await db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE a (id INTEGER PRIMARY KEY);
                CREATE TABLE b (id INTEGER PRIMARY KEY, a_id INTEGER REFERENCES a(id));
                CREATE TABLE c (id INTEGER PRIMARY KEY, a_id INTEGER REFERENCES a(id));
            """)
        }

        let relationships = try await db.read { conn in
            try SchemaRelationshipService.fetchRelationships(db: conn)
        }

        let ids = relationships.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Each SchemaRelationship id must be unique")
    }
}
