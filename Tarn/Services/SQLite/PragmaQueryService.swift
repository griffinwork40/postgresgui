//
//  PragmaQueryService.swift
//  Tarn
//
//  Fetches SQLite health metrics via PRAGMAs and builds DatabaseHealth snapshots.
//  All methods run inside a GRDB Database block (read or write).
//

import Foundation
import GRDB

// MARK: - PragmaQueryService

struct PragmaQueryService {

    // MARK: - Health Snapshot

    /// Fetch a comprehensive health snapshot from the live database.
    ///
    /// - Parameters:
    ///   - db:       An open GRDB `Database` (read access is sufficient for all PRAGMAs).
    ///   - filePath: Absolute path to the database file on disk, or `nil` for in-memory databases.
    /// - Returns:    A fully populated `DatabaseHealth` value.
    static func fetchHealth(db: Database, filePath: String?) throws -> DatabaseHealth {
        // ------------------------------------------------------------------
        // 1. Storage metrics
        // ------------------------------------------------------------------
        let pageSize      = try Int.fetchOne(db, sql: "PRAGMA page_size")      ?? 4096
        let pageCount     = try Int.fetchOne(db, sql: "PRAGMA page_count")     ?? 0
        let freePageCount = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0

        // On-disk file size — 0 for in-memory / path-less databases
        let fileSizeBytes: Int64 = filePath.flatMap { path in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return attrs?[.size] as? Int64
        } ?? 0

        // ------------------------------------------------------------------
        // 2. Journal / WAL
        // ------------------------------------------------------------------
        let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "delete"

        // Detect whether a WAL side-file exists alongside the database file
        let walFile: Bool = filePath.map { path in
            FileManager.default.fileExists(atPath: path + "-wal")
        } ?? false

        // For WAL mode, attempt a passive checkpoint to learn the WAL page count.
        // The result set has columns: busy, log, checkpointed.
        let walPages: Int?
        if journalMode.lowercased() == "wal" {
            let row = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)")
            walPages = row.map { r in r["log"] as? Int ?? 0 }
        } else {
            walPages = nil
        }

        // ------------------------------------------------------------------
        // 3. Configuration PRAGMAs
        // ------------------------------------------------------------------
        let autoVacuumRaw    = try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")    ?? 0
        let autoVacuum       = DatabaseHealth.AutoVacuumMode(rawValue: autoVacuumRaw) ?? .none
        let encoding         = try String.fetchOne(db, sql: "PRAGMA encoding")     ?? "UTF-8"
        let foreignKeysRaw   = try Int.fetchOne(db, sql: "PRAGMA foreign_keys")   ?? 0
        let foreignKeys      = foreignKeysRaw != 0
        let cacheSize        = try Int.fetchOne(db, sql: "PRAGMA cache_size")      ?? 2000
        let mmapSize         = try Int64.fetchOne(db, sql: "PRAGMA mmap_size")     ?? 0

        // ------------------------------------------------------------------
        // 4. Schema statistics
        // ------------------------------------------------------------------
        // Count each object type in one pass. Excludes SQLite internal objects.
        let schemaRows = try Row.fetchAll(db, sql: """
            SELECT type, COUNT(*) AS cnt
            FROM sqlite_schema
            WHERE name NOT LIKE 'sqlite_%'
            GROUP BY type
        """)

        var tableCount   = 0
        var indexCount   = 0
        var viewCount    = 0
        var triggerCount = 0

        for row in schemaRows {
            let type: String = row["type"] ?? ""
            let count: Int   = row["cnt"]  ?? 0
            switch type {
            case "table":   tableCount   = count
            case "index":   indexCount   = count
            case "view":    viewCount    = count
            case "trigger": triggerCount = count
            default:        break
            }
        }

        // ------------------------------------------------------------------
        // 5. Assemble result
        // ------------------------------------------------------------------
        return DatabaseHealth(
            fileSizeBytes:    fileSizeBytes,
            pageSize:         pageSize,
            pageCount:        pageCount,
            freePageCount:    freePageCount,
            journalMode:      journalMode,
            walFile:          walFile,
            walPages:         walPages,
            autoVacuum:       autoVacuum,
            encoding:         encoding,
            foreignKeysEnabled: foreignKeys,
            cacheSize:        cacheSize,
            mmapSize:         mmapSize,
            tableCount:       tableCount,
            indexCount:       indexCount,
            viewCount:        viewCount,
            triggerCount:     triggerCount
        )
    }

    // MARK: - Integrity Checks

    /// Run `PRAGMA integrity_check(N)` — thorough but potentially slow on large databases.
    ///
    /// - Parameters:
    ///   - db:        An open GRDB `Database`.
    ///   - maxErrors: Maximum error messages to collect before stopping (default 100).
    /// - Returns:     An `IntegrityCheckResult` indicating pass/fail and any error messages.
    static func runIntegrityCheck(db: Database, maxErrors: Int = 100) throws -> IntegrityCheckResult {
        try runCheck(db: db, pragma: "integrity_check", maxErrors: maxErrors)
    }

    /// Run `PRAGMA quick_check(N)` — faster than integrity_check; skips cross-index checks.
    ///
    /// - Parameters:
    ///   - db:        An open GRDB `Database`.
    ///   - maxErrors: Maximum error messages to collect before stopping (default 100).
    /// - Returns:     An `IntegrityCheckResult` indicating pass/fail and any error messages.
    static func runQuickCheck(db: Database, maxErrors: Int = 100) throws -> IntegrityCheckResult {
        try runCheck(db: db, pragma: "quick_check", maxErrors: maxErrors)
    }

    // MARK: - Private Helpers

    private static func runCheck(
        db: Database,
        pragma: String,
        maxErrors: Int
    ) throws -> IntegrityCheckResult {
        let start    = Date()
        let sql      = "PRAGMA \(pragma)(\(maxErrors))"
        let messages = try String.fetchAll(db, sql: sql)
        let duration = Date().timeIntervalSince(start)

        // SQLite returns a single row with the text "ok" when the database is healthy.
        let isOK = messages.count == 1 && messages[0] == "ok"

        return IntegrityCheckResult(isOK: isOK, messages: messages, duration: duration)
    }
}
