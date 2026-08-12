//
//  FTSDetectionServiceTests.swift
//  PostgresGUITests
//
//  Tests for FTSDetectionService using in-memory GRDB DatabaseQueue instances.
//

import XCTest
import GRDB
@testable import PostgresGUI

final class FTSDetectionServiceTests: XCTestCase {

    // MARK: - FTS5 detection

    func testDetectsFTS5Table() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE docs USING fts5(title, body)
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertEqual(tables.count, 1)
        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.name, "docs")
        XCTAssertEqual(info.module, .fts5)
    }

    func testFTS5IndexedColumns() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE articles USING fts5(title, body, author)
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.indexedColumns, ["title", "body", "author"])
    }

    func testFTS5WithTokenizer() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE posts USING fts5(title, body, tokenize=porter)")
        }
        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }
        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.tokenizer, "porter")
        XCTAssertFalse(info.indexedColumns.contains(where: { $0.lowercased().hasPrefix("tokenize") }))
    }

    func testFTS5WithContentTable() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE articles (id INTEGER PRIMARY KEY, title TEXT, body TEXT);
                CREATE VIRTUAL TABLE articles_fts USING fts5(
                    title, body,
                    content=articles,
                    content_rowid=id
                )
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.contentTable, "articles")
        XCTAssertEqual(info.indexedColumns, ["title", "body"])
    }

    // MARK: - FTS4 detection

    func testDetectsFTS4Table() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE notes USING fts4(subject, message)
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertEqual(tables.count, 1)
        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.name, "notes")
        XCTAssertEqual(info.module, .fts4)
        XCTAssertEqual(info.indexedColumns, ["subject", "message"])
    }

    func testFTS4WithTokenizer() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE wiki USING fts4(content, tokenize=simple)")
        }
        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }
        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.module, .fts4)
        XCTAssertEqual(info.tokenizer, "simple")
        XCTAssertEqual(info.indexedColumns, ["content"])
    }

    func testFTS4WithContentTable() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE blog_posts (id INTEGER PRIMARY KEY, body TEXT);
                CREATE VIRTUAL TABLE blog_fts USING fts4(content=blog_posts, body)
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.module, .fts4)
        XCTAssertEqual(info.contentTable, "blog_posts")
    }

    // MARK: - FTS3 detection

    func testDetectsFTS3Table() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE legacy_search USING fts3(term, definition)
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertEqual(tables.count, 1)
        let info = try XCTUnwrap(tables.first)
        XCTAssertEqual(info.name, "legacy_search")
        XCTAssertEqual(info.module, .fts3)
        XCTAssertEqual(info.indexedColumns, ["term", "definition"])
    }

    // MARK: - No FTS tables

    func testNoFTSTablesReturnsEmptyArray() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER);
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertTrue(tables.isEmpty, "No FTS tables should produce an empty array")
    }

    func testEmptyDatabaseReturnsEmptyArray() async throws {
        let dbQueue = try DatabaseQueue()

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertTrue(tables.isEmpty)
    }

    // MARK: - Mixed table types

    func testOnlyFTSTablesAreReturnedAmongMixedSchema() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE articles (id INTEGER PRIMARY KEY, title TEXT, body TEXT);
                CREATE VIRTUAL TABLE articles_fts USING fts5(title, body);
                CREATE INDEX idx_articles_title ON articles(title);
                CREATE VIEW recent AS SELECT * FROM articles LIMIT 10;
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].name, "articles_fts")
    }

    func testMultipleFTSTablesReturnedInAlphabeticalOrder() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE zebra_fts USING fts5(content);
                CREATE VIRTUAL TABLE alpha_fts USING fts4(content);
                CREATE VIRTUAL TABLE beta_fts  USING fts3(content);
            """)
        }

        let tables = try await dbQueue.read { db in
            try FTSDetectionService.fetchFTSTables(db: db)
        }

        XCTAssertEqual(tables.count, 3)
        XCTAssertEqual(tables.map(\.name), ["alpha_fts", "beta_fts", "zebra_fts"])
    }

    // MARK: - Direct parse() tests (no database needed)

    func testParseReturnsFTS5ForFTS5Statement() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5(a, b)")
        XCTAssertEqual(info?.module, .fts5)
    }

    func testParseReturnsFTS4ForFTS4Statement() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts4(col1, col2)")
        XCTAssertEqual(info?.module, .fts4)
    }

    func testParseReturnsFTS3ForFTS3Statement() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts3(term)")
        XCTAssertEqual(info?.module, .fts3)
    }

    func testParseReturnsNilForNonFTSStatement() {
        let info = FTSDetectionService.parse(name: "ordinary", createSQL: "CREATE TABLE ordinary (id INTEGER PRIMARY KEY)")
        XCTAssertNil(info)
    }

    func testParseExtractsTokenizerPorter() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5(body, tokenize=porter)")
        XCTAssertEqual(info?.tokenizer, "porter")
    }

    func testParseExtractsTokenizerUnicode61() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5(body, tokenize=unicode61)")
        XCTAssertEqual(info?.tokenizer, "unicode61")
    }

    func testParseExtractsTokenizerQuoted() {
        let info = FTSDetectionService.parse(name: "t", createSQL: #"CREATE VIRTUAL TABLE t USING fts5(body, tokenize="ascii")"#)
        XCTAssertEqual(info?.tokenizer, "ascii")
    }

    func testParseNoTokenizerYieldsNil() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5(title, body)")
        XCTAssertNil(info?.tokenizer)
    }

    func testParseContentTableExtracted() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5(title, content=source_table)")
        XCTAssertEqual(info?.contentTable, "source_table")
    }

    func testParseContentlessTableYieldsNilContentTable() {
        // content="" → contentless FTS, no backing table
        let info = FTSDetectionService.parse(name: "t", createSQL: #"CREATE VIRTUAL TABLE t USING fts5(body, content="")"#)
        XCTAssertNil(info?.contentTable)
    }

    func testParseIndexedColumnsExcludeOptions() {
        let sql = """
            CREATE VIRTUAL TABLE t USING fts5(
                title,
                body,
                author,
                tokenize=porter,
                prefix=2 3
            )
        """
        let info = FTSDetectionService.parse(name: "t", createSQL: sql)
        XCTAssertEqual(info?.indexedColumns, ["title", "body", "author"])
    }

    func testParseEmptyArgListYieldsEmptyColumns() {
        let info = FTSDetectionService.parse(name: "t", createSQL: "CREATE VIRTUAL TABLE t USING fts5()")
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.indexedColumns.isEmpty ?? false)
    }

    // MARK: - buildMatchSQL

    func testBuildMatchSQLForFTS5IncludesRankAndBM25() {
        let info = FTSTableInfo(
            id: "docs", name: "docs", module: .fts5,
            tokenizer: nil, contentTable: nil, indexedColumns: ["body"]
        )
        let sql = FTSDetectionService.buildMatchSQL(table: info, query: "hello")
        XCTAssertTrue(sql.contains("rank AS fts_rank"), "FTS5 SQL should include rank alias")
        XCTAssertTrue(sql.contains("bm25("), "FTS5 SQL should include bm25() call")
        XCTAssertTrue(sql.contains("ORDER BY rank"), "FTS5 SQL should order by rank")
        XCTAssertTrue(sql.contains("MATCH ?"), "SQL should use a ? placeholder")
    }

    func testBuildMatchSQLForFTS4IsSimple() {
        let info = FTSTableInfo(
            id: "notes", name: "notes", module: .fts4,
            tokenizer: nil, contentTable: nil, indexedColumns: ["message"]
        )
        let sql = FTSDetectionService.buildMatchSQL(table: info, query: "world")
        XCTAssertFalse(sql.contains("bm25"), "FTS4 SQL should not include bm25()")
        XCTAssertFalse(sql.contains("fts_rank"), "FTS4 SQL should not include rank alias")
        XCTAssertTrue(sql.contains("MATCH ?"))
    }

    func testBuildMatchSQLForFTS3IsSimple() {
        let info = FTSTableInfo(
            id: "legacy", name: "legacy", module: .fts3,
            tokenizer: nil, contentTable: nil, indexedColumns: ["term"]
        )
        let sql = FTSDetectionService.buildMatchSQL(table: info, query: "term")
        XCTAssertFalse(sql.contains("bm25"))
        XCTAssertTrue(sql.contains("MATCH ?"))
    }

    // MARK: - FTSModule display names and capabilities

    func testFTS5DisplayName() {
        XCTAssertEqual(FTSModule.fts5.displayName, "FTS5")
    }

    func testFTS4DisplayName() {
        XCTAssertEqual(FTSModule.fts4.displayName, "FTS4")
    }

    func testFTS3DisplayName() {
        XCTAssertEqual(FTSModule.fts3.displayName, "FTS3")
    }

    func testFTS5SupportsBM25() {
        XCTAssertTrue(FTSModule.fts5.supportsBM25)
        XCTAssertFalse(FTSModule.fts4.supportsBM25)
        XCTAssertFalse(FTSModule.fts3.supportsBM25)
    }

    func testFTS5SupportsHighlight() {
        XCTAssertTrue(FTSModule.fts5.supportsHighlight)
        XCTAssertFalse(FTSModule.fts4.supportsHighlight)
        XCTAssertFalse(FTSModule.fts3.supportsHighlight)
    }

    func testAllModulesCovered() {
        // Guard against a new case being added without updating capability tests
        XCTAssertEqual(FTSModule.allCases.count, 3)
    }
}
