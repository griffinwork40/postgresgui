//
//  SQLiteDataEditingEdgeCaseTests.swift
//  PostgresGUITests
//
//  Edge-case executor-level tests for SQLiteRowOperations:
//  WITHOUT ROWID tables, STRICT tables, and implicit rowid fallback.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class SQLiteDataEditingEdgeCaseTests: XCTestCase {

    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
    }

    override func tearDown() async throws {
        dbQueue = nil
    }

    // MARK: - WITHOUT ROWID Table

    func testUpdateWithoutRowidTable() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE sessions (
                    session_id TEXT NOT NULL,
                    user_id INTEGER NOT NULL,
                    data TEXT,
                    PRIMARY KEY (session_id)
                ) WITHOUT ROWID;
                INSERT INTO sessions VALUES ('abc123', 42, 'original');
            """)
        }

        let originalRow = TableRow(values: [
            "session_id": "abc123", "user_id": "42", "data": "original"
        ])
        let updated: [String: RowEditValue] = ["data": .value("updated")]

        try await dbQueue.write { db in
            let count = try SQLiteRowOperations.updateRow(
                db: db,
                table: "sessions",
                primaryKeyColumns: ["session_id"],
                originalRow: originalRow,
                updatedValues: updated
            )
            XCTAssertEqual(count, 1)
        }

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT data FROM sessions WHERE session_id = 'abc123'")
        }
        XCTAssertEqual(row?["data"] as String?, "updated")
    }

    func testWithoutRowidTableThrowsWhenNoPKProvided() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE wri (
                    key TEXT NOT NULL PRIMARY KEY,
                    val TEXT
                ) WITHOUT ROWID;
                INSERT INTO wri VALUES ('k1', 'v1');
            """)
        }

        let row = TableRow(values: ["key": "k1", "val": "v1"])
        do {
            try await dbQueue.write { db in
                _ = try SQLiteRowOperations.deleteRows(
                    db: db,
                    table: "wri",
                    primaryKeyColumns: [],   // no explicit PK → fallback attempted
                    rows: [row]
                )
            }
            XCTFail("Expected RowOperationError.noPrimaryKey for WITHOUT ROWID table")
        } catch RowOperationError.noPrimaryKey {
            // Correct — can't fall back to rowid for WITHOUT ROWID table
        }
    }

    // MARK: - STRICT Table

    func testStrictTableTypeValidation() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE strict_items (
                    id INTEGER PRIMARY KEY,
                    label TEXT NOT NULL,
                    count INTEGER
                ) STRICT;
            """)
        }

        let values: [String: RowEditValue] = [
            "id": .value("1"),
            "label": .value("Widget"),
            "count": .value("5")
        ]

        let count = try await dbQueue.write { db in
            try SQLiteRowOperations.insertRow(db: db, table: "strict_items", values: values)
        }
        XCTAssertEqual(count, 1)

        let row = try await dbQueue.read { db -> Row? in
            try Row.fetchOne(db, sql: "SELECT * FROM strict_items WHERE id = 1")
        }
        XCTAssertEqual(row?["label"] as String?, "Widget")
        XCTAssertEqual(row?["count"] as Int64?, 5)
    }

    // MARK: - Implicit rowid fallback

    func testDeleteUsesRowidFallbackWhenNoPKProvided() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE notes (content TEXT);
                INSERT INTO notes VALUES ('note one');
                INSERT INTO notes VALUES ('note two');
            """)
        }

        let rowidValue = try await dbQueue.read { db -> Int64 in
            let r = try Row.fetchOne(db, sql: "SELECT rowid FROM notes WHERE content = 'note one'")!
            return r["rowid"]
        }

        let rowWithRowid = TableRow(values: ["rowid": "\(rowidValue)", "content": "note one"])

        let affected = try await dbQueue.write { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: "notes",
                primaryKeyColumns: [],   // triggers rowid fallback
                rows: [rowWithRowid]
            )
        }
        XCTAssertEqual(affected, 1)

        let remaining = try await dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes")!
        }
        XCTAssertEqual(remaining, 1)
    }
}
