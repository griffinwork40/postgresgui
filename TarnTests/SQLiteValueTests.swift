//
//  SQLiteValueTests.swift
//  TarnTests
//
//  Tests for the typed value model: SQLiteValue, ResultRow, ResultColumn, TypedQueryResult.
//

import XCTest
@testable import Tarn

final class SQLiteValueTests: XCTestCase {

    // MARK: - SQLiteValue Display String

    func testNullDisplayString() {
        XCTAssertNil(SQLiteValue.null.displayString)
    }

    func testIntegerDisplayString() {
        XCTAssertEqual(SQLiteValue.integer(42).displayString, "42")
        XCTAssertEqual(SQLiteValue.integer(-1).displayString, "-1")
        XCTAssertEqual(SQLiteValue.integer(0).displayString, "0")
        XCTAssertEqual(SQLiteValue.integer(Int64.max).displayString, "\(Int64.max)")
    }

    func testRealDisplayString() {
        XCTAssertEqual(SQLiteValue.real(3.14).displayString, "3.14")
        XCTAssertEqual(SQLiteValue.real(0.0).displayString, "0.0")
        XCTAssertEqual(SQLiteValue.real(-2.5).displayString, "-2.5")
    }

    func testTextDisplayString() {
        XCTAssertEqual(SQLiteValue.text("hello").displayString, "hello")
        XCTAssertEqual(SQLiteValue.text("").displayString, "")
        XCTAssertEqual(SQLiteValue.text("with spaces").displayString, "with spaces")
    }

    func testBlobDisplayString() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(SQLiteValue.blob(data).displayString, "[BLOB: 4 bytes]")
        XCTAssertEqual(SQLiteValue.blob(Data()).displayString, "[BLOB: 0 bytes]")
    }

    // MARK: - SQLiteValue Storage Class Names

    func testStorageClassNames() {
        XCTAssertEqual(SQLiteValue.null.storageClassName, "NULL")
        XCTAssertEqual(SQLiteValue.integer(1).storageClassName, "INTEGER")
        XCTAssertEqual(SQLiteValue.real(1.0).storageClassName, "REAL")
        XCTAssertEqual(SQLiteValue.text("").storageClassName, "TEXT")
        XCTAssertEqual(SQLiteValue.blob(Data()).storageClassName, "BLOB")
    }

    // MARK: - SQLiteValue Equality

    func testEquality() {
        XCTAssertEqual(SQLiteValue.null, SQLiteValue.null)
        XCTAssertEqual(SQLiteValue.integer(42), SQLiteValue.integer(42))
        XCTAssertNotEqual(SQLiteValue.integer(42), SQLiteValue.integer(43))
        XCTAssertNotEqual(SQLiteValue.integer(0), SQLiteValue.real(0.0))
        XCTAssertNotEqual(SQLiteValue.text("42"), SQLiteValue.integer(42))
        XCTAssertEqual(SQLiteValue.blob(Data([1, 2])), SQLiteValue.blob(Data([1, 2])))
        XCTAssertNotEqual(SQLiteValue.blob(Data([1, 2])), SQLiteValue.blob(Data([1, 3])))
    }

    // MARK: - ResultRow

    func testResultRowSubscript() {
        let row = ResultRow(values: [.integer(1), .text("hello"), .null])
        XCTAssertEqual(row[0], .integer(1))
        XCTAssertEqual(row[1], .text("hello"))
        XCTAssertEqual(row[2], .null)
    }

    func testResultRowHasStableId() {
        let id = UUID()
        let row = ResultRow(id: id, values: [.integer(1)])
        XCTAssertEqual(row.id, id)
    }

    // MARK: - ResultColumn

    func testResultColumnEquality() {
        let a = ResultColumn(name: "id", declaredType: "INTEGER")
        let b = ResultColumn(name: "id", declaredType: "INTEGER")
        let c = ResultColumn(name: "id", declaredType: "TEXT")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - TypedQueryResult

    func testSuccessResult() {
        let columns = [ResultColumn(name: "id"), ResultColumn(name: "name")]
        let rows = [ResultRow(values: [.integer(1), .text("Alice")])]
        let result = TypedQueryResult.success(
            columns: columns,
            rows: rows,
            executionTime: 0.05
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.columnNames, ["id", "name"])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertNil(result.affectedRows)
    }

    func testFailureResult() {
        let result = TypedQueryResult.failure(
            error: FileOpenError.notConnected,
            executionTime: 0.01
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.columns.isEmpty)
        XCTAssertTrue(result.rows.isEmpty)
    }

    func testAffectedRowsResult() {
        let result = TypedQueryResult.success(
            columns: [],
            rows: [],
            executionTime: 0.01,
            affectedRows: 5
        )
        XCTAssertEqual(result.affectedRows, 5)
    }

    // MARK: - Duplicate Column Names

    func testDuplicateColumnNamesPreserved() {
        let columns = [
            ResultColumn(name: "id"),
            ResultColumn(name: "id"),
            ResultColumn(name: "name")
        ]
        let row = ResultRow(values: [.integer(1), .integer(2), .text("Alice")])
        let result = TypedQueryResult.success(
            columns: columns,
            rows: [row],
            executionTime: 0.01
        )

        // Both "id" columns are preserved
        XCTAssertEqual(result.columnNames, ["id", "id", "name"])
        // Values are accessible by position
        XCTAssertEqual(result.rows[0][0], .integer(1))
        XCTAssertEqual(result.rows[0][1], .integer(2))
    }

    // MARK: - Presentation Conversion

    func testToDisplayRow() {
        let columns = [
            ResultColumn(name: "id"),
            ResultColumn(name: "name"),
            ResultColumn(name: "score"),
            ResultColumn(name: "data")
        ]
        let row = ResultRow(values: [
            .integer(42),
            .text("Alice"),
            .null,
            .blob(Data([0xFF]))
        ])

        let display = row.toDisplayRow(columns: columns)
        XCTAssertEqual(display.values["id"], "42")
        XCTAssertEqual(display.values["name"], "Alice")
        XCTAssertEqual(display.values["score"], .some(nil))  // NULL → nil in dict
        XCTAssertEqual(display.values["data"], "[BLOB: 1 bytes]")
    }

    func testToDisplayRowDuplicateColumnsLastWins() {
        let columns = [
            ResultColumn(name: "id"),
            ResultColumn(name: "id")
        ]
        let row = ResultRow(values: [.integer(1), .integer(2)])
        let display = row.toDisplayRow(columns: columns)

        // Dictionary can only hold one "id" — last one wins
        XCTAssertEqual(display.values["id"], "2")
    }

    func testTypedQueryResultToQueryResult() {
        let columns = [ResultColumn(name: "x")]
        let rows = [ResultRow(values: [.integer(99)])]
        let typed = TypedQueryResult.success(
            columns: columns,
            rows: rows,
            executionTime: 0.05
        )

        let legacy = typed.toQueryResult()
        XCTAssertTrue(legacy.isSuccess)
        XCTAssertEqual(legacy.columnNames, ["x"])
        XCTAssertEqual(legacy.rows.count, 1)
        XCTAssertEqual(legacy.rows[0].values["x"], "99")
        XCTAssertEqual(legacy.executionTime, 0.05)
    }

    func testFailureTypedQueryResultToQueryResult() {
        let typed = TypedQueryResult.failure(
            error: FileOpenError.notConnected,
            executionTime: 0.01
        )
        let legacy = typed.toQueryResult()
        XCTAssertFalse(legacy.isSuccess)
        XCTAssertNotNil(legacy.error)
    }
}
