//
//  EQPParserTests.swift
//  TarnTests
//
//  Tests for EXPLAIN QUERY PLAN parser.
//

import XCTest
@testable import Tarn

final class EQPParserTests: XCTestCase {

    // MARK: - Dictionary-based parsing

    func testParseSingleScanNode() {
        let rows: [[String: String]] = [
            ["id": "2", "parent": "0", "detail": "SCAN t1"]
        ]
        let nodes = EQPParser.parse(rows: rows)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].detail, "SCAN t1")
        XCTAssertEqual(nodes[0].id, 2)
        XCTAssertEqual(nodes[0].parentId, 0)
        XCTAssertTrue(nodes[0].children.isEmpty)
    }

    func testParseTwoSiblings() {
        let rows: [[String: String]] = [
            ["id": "2", "parent": "0", "detail": "SEARCH t1 USING INDEX i1 (a=?)"],
            ["id": "3", "parent": "0", "detail": "SCAN t2"]
        ]
        let nodes = EQPParser.parse(rows: rows)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].detail, "SEARCH t1 USING INDEX i1 (a=?)")
        XCTAssertEqual(nodes[1].detail, "SCAN t2")
    }

    func testParseNestedTree() {
        // MULTI-INDEX OR with two children
        let rows: [[String: String]] = [
            ["id": "5", "parent": "0", "detail": "MULTI-INDEX OR"],
            ["id": "8", "parent": "5", "detail": "SEARCH t1 USING COVERING INDEX i2 (a=?)"],
            ["id": "16", "parent": "5", "detail": "SEARCH t1 USING INDEX i3 (b=?)"]
        ]
        let nodes = EQPParser.parse(rows: rows)
        XCTAssertEqual(nodes.count, 1, "Root should be MULTI-INDEX OR")
        XCTAssertEqual(nodes[0].detail, "MULTI-INDEX OR")
        XCTAssertEqual(nodes[0].children.count, 2)
        XCTAssertEqual(nodes[0].children[0].detail, "SEARCH t1 USING COVERING INDEX i2 (a=?)")
        XCTAssertEqual(nodes[0].children[1].detail, "SEARCH t1 USING INDEX i3 (b=?)")
    }

    func testParseCompoundQueryWithSubqueries() {
        let rows: [[String: String]] = [
            ["id": "2", "parent": "0", "detail": "CO-ROUTINE qqq"],
            ["id": "6", "parent": "2", "detail": "SCAN t1 USING COVERING INDEX i2"],
            ["id": "25", "parent": "0", "detail": "SCAN qqq"],
            ["id": "46", "parent": "0", "detail": "USE TEMP B-TREE FOR GROUP BY"]
        ]
        let nodes = EQPParser.parse(rows: rows)
        XCTAssertEqual(nodes.count, 3, "Three root-level nodes")
        XCTAssertEqual(nodes[0].detail, "CO-ROUTINE qqq")
        XCTAssertEqual(nodes[0].children.count, 1)
        XCTAssertEqual(nodes[0].children[0].detail, "SCAN t1 USING COVERING INDEX i2")
        XCTAssertEqual(nodes[1].detail, "SCAN qqq")
        XCTAssertEqual(nodes[2].detail, "USE TEMP B-TREE FOR GROUP BY")
    }

    func testParseEmptyRows() {
        let nodes = EQPParser.parse(rows: [])
        XCTAssertTrue(nodes.isEmpty)
    }

    func testParseMalformedRowsSkipped() {
        let rows: [[String: String]] = [
            ["id": "2", "parent": "0", "detail": "SCAN t1"],
            ["id": "bad", "parent": "0", "detail": "SHOULD BE SKIPPED"],
            ["id": "3", "parent": "0", "detail": "SCAN t2"]
        ]
        let nodes = EQPParser.parse(rows: rows)
        XCTAssertEqual(nodes.count, 2)
    }

    // MARK: - TableRow-based parsing

    func testParseTableRows() {
        let columnNames = ["id", "parent", "notused", "detail"]
        let tableRows: [TableRow] = [
            TableRow(values: ["id": "2", "parent": "0", "notused": "0", "detail": "SCAN users"]),
            TableRow(values: ["id": "3", "parent": "0", "notused": "0", "detail": "SEARCH orders USING INDEX idx (user_id=?)"])
        ]
        let nodes = EQPParser.parse(tableRows: tableRows, columnNames: columnNames)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].detail, "SCAN users")
        XCTAssertEqual(nodes[1].detail, "SEARCH orders USING INDEX idx (user_id=?)")
    }

    func testParseTableRowsMissingColumns() {
        let columnNames = ["foo", "bar"]
        let tableRows: [TableRow] = [
            TableRow(values: ["foo": "1", "bar": "2"])
        ]
        let nodes = EQPParser.parse(tableRows: tableRows, columnNames: columnNames)
        XCTAssertTrue(nodes.isEmpty, "Should return empty when required columns missing")
    }

    // MARK: - Text-based parsing

    func testParseSimpleTextPlan() {
        let text = """
        QUERY PLAN
        `--SCAN t1
        """
        let nodes = EQPParser.parseText(text)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].detail, "SCAN t1")
    }

    func testParseTextPlanWithSiblings() {
        let text = """
        QUERY PLAN
        |--SEARCH t1 USING INDEX i2 (a=? AND b>?)
        `--SCAN t2
        """
        let nodes = EQPParser.parseText(text)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].detail, "SEARCH t1 USING INDEX i2 (a=? AND b>?)")
        XCTAssertEqual(nodes[1].detail, "SCAN t2")
    }

    func testParseTextPlanWithNesting() {
        let text = """
        QUERY PLAN
        `--MULTI-INDEX OR
           |--SEARCH t1 USING COVERING INDEX i2 (a=?)
           `--SEARCH t1 USING INDEX i3 (b=?)
        """
        let nodes = EQPParser.parseText(text)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].detail, "MULTI-INDEX OR")
        XCTAssertEqual(nodes[0].children.count, 2)
        XCTAssertEqual(nodes[0].children[0].detail, "SEARCH t1 USING COVERING INDEX i2 (a=?)")
        XCTAssertEqual(nodes[0].children[1].detail, "SEARCH t1 USING INDEX i3 (b=?)")
    }

    func testParseTextPlanDeepNesting() {
        let text = """
        QUERY PLAN
        |--CO-ROUTINE qqq
        |  `--SCAN t1 USING COVERING INDEX i2
        |--SCAN qqq
        `--USE TEMP B-TREE FOR GROUP BY
        """
        let nodes = EQPParser.parseText(text)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0].detail, "CO-ROUTINE qqq")
        XCTAssertEqual(nodes[0].children.count, 1)
        XCTAssertEqual(nodes[0].children[0].detail, "SCAN t1 USING COVERING INDEX i2")
        XCTAssertEqual(nodes[1].detail, "SCAN qqq")
        XCTAssertEqual(nodes[2].detail, "USE TEMP B-TREE FOR GROUP BY")
    }

    func testParseEmptyText() {
        let nodes = EQPParser.parseText("")
        XCTAssertTrue(nodes.isEmpty)
    }

    func testParseTextWithOnlyHeader() {
        let nodes = EQPParser.parseText("QUERY PLAN")
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Operation classification

    func testOperationClassification() {
        XCTAssertEqual(EQPOperation.classify("SCAN t1"), .scan)
        XCTAssertEqual(EQPOperation.classify("SCAN t1 USING INDEX idx"), .indexScan)
        XCTAssertEqual(EQPOperation.classify("SCAN t1 USING COVERING INDEX idx"), .indexScan)
        XCTAssertEqual(EQPOperation.classify("SEARCH t1 USING INDEX idx (a=?)"), .search)
        XCTAssertEqual(EQPOperation.classify("SEARCH t1 USING COVERING INDEX idx (a=?)"), .coveringSearch)
        XCTAssertEqual(EQPOperation.classify("SEARCH t1 USING INTEGER PRIMARY KEY (rowid=?)"), .search)
        XCTAssertEqual(EQPOperation.classify("USE TEMP B-TREE FOR ORDER BY"), .tempBTree)
        XCTAssertEqual(EQPOperation.classify("USE TEMP B-TREE FOR GROUP BY"), .tempBTree)
        XCTAssertEqual(EQPOperation.classify("USE TEMP B-TREE FOR DISTINCT"), .tempBTree)
        XCTAssertEqual(EQPOperation.classify("CO-ROUTINE qqq"), .subquery)
        XCTAssertEqual(EQPOperation.classify("MATERIALIZE sub1"), .subquery)
        XCTAssertEqual(EQPOperation.classify("SCALAR SUBQUERY 1"), .subquery)
        XCTAssertEqual(EQPOperation.classify("CORRELATED SCALAR SUBQUERY 2"), .subquery)
        XCTAssertEqual(EQPOperation.classify("COMPOUND QUERY"), .compound)
        XCTAssertEqual(EQPOperation.classify("MERGE (UNION)"), .compound)
        XCTAssertEqual(EQPOperation.classify("SCAN CONSTANT ROW"), .scan)
        XCTAssertEqual(EQPOperation.classify("MULTI-INDEX OR"), .other)
    }

    func testOperationLabels() {
        XCTAssertEqual(EQPOperation.scan.label, "FULL SCAN")
        XCTAssertEqual(EQPOperation.search.label, "INDEX")
        XCTAssertEqual(EQPOperation.coveringSearch.label, "INDEX ONLY")
        XCTAssertEqual(EQPOperation.tempBTree.label, "TEMP SORT")
        XCTAssertEqual(EQPOperation.other.label, "")
    }
}
