//
//  AttachedDatabaseServiceTests.swift
//  TarnTests
//
//  Tests for AttachedDatabaseService using in-memory GRDB DatabaseQueue instances.
//  Attach/detach tests require a temporary on-disk file because SQLite cannot
//  attach one in-memory database to another in-memory connection.
//

import XCTest
import GRDB
@testable import Tarn

final class AttachedDatabaseServiceTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachedDBTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    /// Create a minimal SQLite database file and return its path.
    private func makeDatabaseFile(name: String, tables: [String] = []) throws -> String {
        let path = tempDir.appendingPathComponent(name).path
        let queue = try DatabaseQueue(path: path)
        if !tables.isEmpty {
            try queue.write { db in
                for table in tables {
                    try db.execute(sql: """
                        CREATE TABLE \(table) (id INTEGER PRIMARY KEY, value TEXT)
                    """)
                }
            }
        }
        return path
    }

    // MARK: - PRAGMA database_list: "main" is always present

    func testListAttachedDatabasesAlwaysContainsMain() throws {
        let dbQueue = try DatabaseQueue()
        let databases = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        XCTAssertTrue(
            databases.contains(where: { $0.alias == "main" }),
            "PRAGMA database_list must always include 'main'"
        )
    }

    func testListAttachedDatabasesMainIsMarkedIsMain() throws {
        let dbQueue = try DatabaseQueue()
        let databases = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        let main = databases.first(where: { $0.alias == "main" })
        XCTAssertNotNil(main)
        XCTAssertTrue(main!.isMain)
        XCTAssertFalse(main!.isTemp)
        XCTAssertTrue(main!.isReserved)
    }

    func testListAttachedDatabasesContainsTempEntry() throws {
        let dbQueue = try DatabaseQueue()
        let databases = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        // In-memory DatabaseQueue always has both "main" and "temp".
        let temp = databases.first(where: { $0.alias == "temp" })
        XCTAssertNotNil(temp, "PRAGMA database_list should include 'temp'")
        XCTAssertTrue(temp!.isTemp)
        XCTAssertTrue(temp!.isReserved)
    }

    func testListAttachedDatabasesOrderedBySeq() throws {
        let dbQueue = try DatabaseQueue()
        let databases = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        let seqs = databases.map(\.seq)
        XCTAssertEqual(seqs, seqs.sorted(), "Results must be ordered by seq ascending")
    }

    // MARK: - Attach / Detach Lifecycle

    func testAttachAndDetach() throws {
        let primaryPath = try makeDatabaseFile(name: "primary.db")
        let secondaryPath = try makeDatabaseFile(name: "secondary.db", tables: ["items"])

        let dbQueue = try DatabaseQueue(path: primaryPath)

        // Attach
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "aux"
            )
        }

        // Verify it appears in the list
        let afterAttach = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        XCTAssertTrue(afterAttach.contains(where: { $0.alias == "aux" }))

        // Detach
        try dbQueue.write { db in
            try AttachedDatabaseService.detachDatabase(db: db, alias: "aux")
        }

        // Verify it is gone
        let afterDetach = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        XCTAssertFalse(afterDetach.contains(where: { $0.alias == "aux" }))
    }

    func testAttachedDatabaseFilePathIsRecorded() throws {
        let primaryPath   = try makeDatabaseFile(name: "main.db")
        let secondaryPath = try makeDatabaseFile(name: "logs.db")

        let dbQueue = try DatabaseQueue(path: primaryPath)
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "logs"
            )
        }

        let databases = try dbQueue.read { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
        let logsEntry = databases.first(where: { $0.alias == "logs" })
        XCTAssertNotNil(logsEntry)
        // SQLite normalises the path; just verify it ends with the filename.
        XCTAssertTrue(
            logsEntry!.filePath.hasSuffix("logs.db"),
            "filePath should contain the attached file name"
        )
    }

    // MARK: - Tables for Attached Database

    func testFetchTablesForAttachedReturnsCorrectTables() throws {
        let primaryPath   = try makeDatabaseFile(name: "primary2.db")
        let secondaryPath = try makeDatabaseFile(
            name: "secondary2.db",
            tables: ["events", "users"]
        )

        let dbQueue = try DatabaseQueue(path: primaryPath)
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "ext"
            )
        }

        let tables = try dbQueue.read { db in
            try AttachedDatabaseService.fetchTablesForAttached(db: db, alias: "ext")
        }

        let names = tables.map(\.name).sorted()
        XCTAssertEqual(names, ["events", "users"])
    }

    func testFetchTablesForAttachedSetsSchema() throws {
        let primaryPath   = try makeDatabaseFile(name: "p3.db")
        let secondaryPath = try makeDatabaseFile(name: "s3.db", tables: ["things"])

        let dbQueue = try DatabaseQueue(path: primaryPath)
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "ext3"
            )
        }

        let tables = try dbQueue.read { db in
            try AttachedDatabaseService.fetchTablesForAttached(db: db, alias: "ext3")
        }

        XCTAssertTrue(tables.allSatisfy { $0.schema == "ext3" },
            "All tables must use the alias as their schema for qualified name construction")
    }

    func testFetchTablesForAttachedEmptyDatabase() throws {
        let primaryPath   = try makeDatabaseFile(name: "p4.db")
        let secondaryPath = try makeDatabaseFile(name: "empty.db")

        let dbQueue = try DatabaseQueue(path: primaryPath)
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "empty"
            )
        }

        let tables = try dbQueue.read { db in
            try AttachedDatabaseService.fetchTablesForAttached(db: db, alias: "empty")
        }

        XCTAssertEqual(tables.count, 0, "Empty database should have no tables")
    }

    func testFetchTablesForAttachedIncludesViews() throws {
        let primaryPath   = try makeDatabaseFile(name: "p5.db")
        let secondaryPath = try makeDatabaseFile(name: "withviews.db", tables: ["data"])
        let secondaryQueue = try DatabaseQueue(path: secondaryPath)
        try secondaryQueue.write { db in
            try db.execute(sql: "CREATE VIEW data_view AS SELECT * FROM data")
        }

        let dbQueue = try DatabaseQueue(path: primaryPath)
        try dbQueue.write { db in
            try AttachedDatabaseService.attachDatabase(
                db: db, filePath: secondaryPath, alias: "withviews"
            )
        }

        let tables = try dbQueue.read { db in
            try AttachedDatabaseService.fetchTablesForAttached(db: db, alias: "withviews")
        }

        let types = Set(tables.map(\.tableType))
        XCTAssertTrue(types.contains(.regular))
        XCTAssertTrue(types.contains(.view))
    }

    // MARK: - Alias Validation

    func testValidateAliasAcceptsSimpleIdentifier() {
        XCTAssertNoThrow(try AttachedDatabaseService.validateAlias("logs"))
        XCTAssertNoThrow(try AttachedDatabaseService.validateAlias("my_db"))
        XCTAssertNoThrow(try AttachedDatabaseService.validateAlias("_private"))
        XCTAssertNoThrow(try AttachedDatabaseService.validateAlias("DB2"))
    }

    func testValidateAliasRejectsReservedMain() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("main")) { error in
            guard case AttachedDatabaseError.reservedAlias = error else {
                XCTFail("Expected .reservedAlias, got \(error)")
                return
            }
        }
    }

    func testValidateAliasRejectsReservedMainCaseInsensitive() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("MAIN"))
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("Main"))
    }

    func testValidateAliasRejectsReservedTemp() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("temp")) { error in
            guard case AttachedDatabaseError.reservedAlias = error else {
                XCTFail("Expected .reservedAlias, got \(error)")
                return
            }
        }
    }

    func testValidateAliasRejectsEmpty() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("")) { error in
            guard case AttachedDatabaseError.invalidAlias = error else {
                XCTFail("Expected .invalidAlias, got \(error)")
                return
            }
        }
    }

    func testValidateAliasRejectsLeadingDigit() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("1bad")) { error in
            guard case AttachedDatabaseError.invalidAlias = error else {
                XCTFail("Expected .invalidAlias, got \(error)")
                return
            }
        }
    }

    func testValidateAliasRejectsHyphens() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("my-db"))
    }

    func testValidateAliasRejectsSpaces() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("my db"))
    }

    func testValidateAliasRejectsDots() {
        XCTAssertThrowsError(try AttachedDatabaseService.validateAlias("db.ext"))
    }

    // MARK: - AttachedDatabase Model

    func testAttachedDatabaseDisplayFileName() {
        let a = AttachedDatabase(seq: 0, alias: "main", filePath: "/Users/g/data.sqlite")
        XCTAssertEqual(a.displayFileName, "data.sqlite")
    }

    func testAttachedDatabaseDisplayFileNameForEmpty() {
        let temp = AttachedDatabase(seq: 1, alias: "temp", filePath: "")
        XCTAssertEqual(temp.displayFileName, "(temporary)")

        let mem = AttachedDatabase(seq: 2, alias: "aux", filePath: "")
        XCTAssertEqual(mem.displayFileName, "(in-memory)")
    }

    func testAttachedDatabaseEquatableById() {
        let a = AttachedDatabase(seq: 0, alias: "logs", filePath: "/a/logs.db")
        let b = AttachedDatabase(seq: 0, alias: "logs", filePath: "/a/logs.db")
        XCTAssertEqual(a, b)

        let c = AttachedDatabase(seq: 1, alias: "other", filePath: "/a/logs.db")
        XCTAssertNotEqual(a, c)
    }
}
