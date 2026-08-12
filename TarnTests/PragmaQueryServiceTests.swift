//
//  PragmaQueryServiceTests.swift
//  TarnTests
//
//  Tests for PragmaQueryService using in-memory GRDB DatabaseQueue instances.
//  In-memory databases have no file path, so file-related fields (fileSizeBytes,
//  walFile) always return their zero/false defaults.
//

import XCTest
import GRDB
@testable import Tarn

final class PragmaQueryServiceTests: XCTestCase {

    // MARK: - Basic health fetch

    func testFetchHealthReturnsValidData() async throws {
        let dbQueue = try DatabaseQueue()     // in-memory
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        // Page size must be a power of two between 512 and 65536
        XCTAssertGreaterThan(health.pageSize, 0)
        XCTAssertTrue([512, 1024, 2048, 4096, 8192, 16384, 32768, 65536].contains(health.pageSize))

        // Free page count cannot exceed total page count
        XCTAssertGreaterThanOrEqual(health.pageCount, health.freePageCount)

        // In-memory: no file path → file size is 0
        XCTAssertEqual(health.fileSizeBytes, 0)

        // In-memory: no WAL side-file
        XCTAssertFalse(health.walFile)
    }

    // MARK: - Page metrics

    func testFetchHealthPageMetrics() async throws {
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        XCTAssertGreaterThan(health.pageSize, 0)
        XCTAssertGreaterThanOrEqual(health.pageCount, 0)
        XCTAssertGreaterThanOrEqual(health.freePageCount, 0)
        XCTAssertGreaterThanOrEqual(health.fragmentationPercent, 0.0)
        XCTAssertLessThanOrEqual(health.fragmentationPercent, 100.0)
    }

    // MARK: - Journal mode

    func testFetchHealthJournalMode() async throws {
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        // SQLite always returns a non-empty journal mode string
        XCTAssertFalse(health.journalMode.isEmpty)

        // For an in-memory database the default is "memory"
        XCTAssertEqual(health.journalMode, "memory")

        // WAL info should be nil for non-WAL databases
        XCTAssertNil(health.walPages)
    }

    // MARK: - Schema statistics

    func testFetchHealthSchemaStats() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE articles (id INTEGER PRIMARY KEY, title TEXT);
                CREATE TABLE tags     (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE article_tags (article_id INTEGER, tag_id INTEGER);
                CREATE VIEW tagged_articles AS
                    SELECT a.title, t.name
                    FROM articles a
                    JOIN article_tags at ON at.article_id = a.id
                    JOIN tags t ON t.id = at.tag_id;
                CREATE INDEX idx_articles_title ON articles(title);
                CREATE INDEX idx_tags_name      ON tags(name);
            """)
        }

        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        XCTAssertEqual(health.tableCount, 3,
            "Expected 3 tables (articles, tags, article_tags)")
        XCTAssertEqual(health.viewCount, 1,
            "Expected 1 view (tagged_articles)")
        XCTAssertEqual(health.indexCount, 2,
            "Expected 2 explicit indexes (idx_articles_title, idx_tags_name)")
        XCTAssertEqual(health.triggerCount, 0,
            "Expected 0 triggers")
    }

    func testFetchHealthSchemaStatsTriggerCount() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE events (id INTEGER PRIMARY KEY, name TEXT, fired_at TEXT);
                CREATE TABLE audit  (id INTEGER PRIMARY KEY, event_id INTEGER, ts TEXT);
                CREATE TRIGGER trg_after_event
                    AFTER INSERT ON events
                BEGIN
                    INSERT INTO audit(event_id, ts) VALUES (NEW.id, datetime('now'));
                END;
            """)
        }

        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        XCTAssertEqual(health.triggerCount, 1)
    }

    // MARK: - Integrity checks

    func testRunIntegrityCheckPasses() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE items (id INTEGER PRIMARY KEY, value TEXT);
                INSERT INTO items VALUES (1, 'a');
                INSERT INTO items VALUES (2, 'b');
            """)
        }

        let result = try await dbQueue.read { db in
            try PragmaQueryService.runIntegrityCheck(db: db)
        }

        XCTAssertTrue(result.isOK)
        XCTAssertEqual(result.messages, ["ok"])
        XCTAssertGreaterThanOrEqual(result.duration, 0.0)
    }

    func testRunQuickCheckPasses() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE widgets (id INTEGER PRIMARY KEY, label TEXT NOT NULL);
                INSERT INTO widgets VALUES (1, 'foo');
            """)
        }

        let result = try await dbQueue.read { db in
            try PragmaQueryService.runQuickCheck(db: db)
        }

        XCTAssertTrue(result.isOK)
        XCTAssertEqual(result.messages, ["ok"])
    }

    // MARK: - Empty database

    func testFetchHealthOnEmptyDatabase() async throws {
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        // Schema counts should all be zero on a brand-new database
        XCTAssertEqual(health.tableCount, 0)
        XCTAssertEqual(health.indexCount, 0)
        XCTAssertEqual(health.viewCount, 0)
        XCTAssertEqual(health.triggerCount, 0)

        // Storage fields should still be valid
        XCTAssertGreaterThan(health.pageSize, 0)
        XCTAssertGreaterThanOrEqual(health.pageCount, 0)
    }

    // MARK: - Foreign keys default

    func testFetchHealthForeignKeysDefault() async throws {
        // GRDB's default Configuration sets foreignKeysEnabled = true,
        // so PRAGMA foreign_keys is 1 (ON) when using a plain DatabaseQueue().
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        XCTAssertTrue(health.foreignKeysEnabled,
            "GRDB enables PRAGMA foreign_keys by default (Configuration.foreignKeysEnabled = true)")
    }

    // MARK: - Configuration PRAGMAs

    func testFetchHealthConfigurationFields() async throws {
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }

        // Encoding should be a non-empty string
        XCTAssertFalse(health.encoding.isEmpty)

        // Auto-vacuum raw value should map to a known mode
        let knownModes: [DatabaseHealth.AutoVacuumMode] = [.none, .full, .incremental]
        XCTAssertTrue(knownModes.contains(health.autoVacuum),
            "auto_vacuum PRAGMA returned an unexpected value")

        // Cache size is returned as a number of pages (may be negative for kibibytes)
        // Just verify the field is readable
        XCTAssertNotNil(health.cacheSize)

        // mmap_size is ≥ 0
        XCTAssertGreaterThanOrEqual(health.mmapSize, 0)
    }

    // MARK: - Integrity check with max errors

    func testIntegrityCheckUsesMaxErrors() async throws {
        // Verify the API accepts a maxErrors parameter without crashing
        let dbQueue = try DatabaseQueue()
        let result = try await dbQueue.read { db in
            try PragmaQueryService.runIntegrityCheck(db: db, maxErrors: 10)
        }
        // A freshly-created database must pass
        XCTAssertTrue(result.isOK)
    }

    func testQuickCheckUsesMaxErrors() async throws {
        let dbQueue = try DatabaseQueue()
        let result = try await dbQueue.read { db in
            try PragmaQueryService.runQuickCheck(db: db, maxErrors: 5)
        }
        XCTAssertTrue(result.isOK)
    }

    // MARK: - File path nil vs provided

    func testFetchHealthNilFilePathProducesZeroFileSize() async throws {
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: nil)
        }
        XCTAssertEqual(health.fileSizeBytes, 0)
        XCTAssertFalse(health.walFile)
    }

    func testFetchHealthNonExistentFilePathProducesZeroFileSize() async throws {
        // A path that does not exist should not crash — it falls back to 0
        let dbQueue = try DatabaseQueue()
        let health = try await dbQueue.read { db in
            try PragmaQueryService.fetchHealth(
                db: db,
                filePath: "/tmp/does_not_exist_\(UUID().uuidString).sqlite"
            )
        }
        XCTAssertEqual(health.fileSizeBytes, 0)
        XCTAssertFalse(health.walFile)
    }
}
