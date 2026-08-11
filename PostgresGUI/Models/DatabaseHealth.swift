//
//  DatabaseHealth.swift
//  PostgresGUI
//
//  Data models for the PRAGMA-based database health dashboard.
//

import Foundation

// MARK: - DatabaseHealth

/// A snapshot of a SQLite database's health metrics gathered from PRAGMAs.
struct DatabaseHealth: Sendable {

    // MARK: Storage metrics

    /// On-disk file size in bytes (0 when the database has no file path, e.g. in-memory).
    let fileSizeBytes: Int64

    /// Size of each page in bytes (PRAGMA page_size).
    let pageSize: Int

    /// Total allocated pages (PRAGMA page_count).
    let pageCount: Int

    /// Number of unused (free-list) pages (PRAGMA freelist_count).
    let freePageCount: Int

    /// Percentage of pages that are free. 0.0 when pageCount is zero.
    var fragmentationPercent: Double {
        guard pageCount > 0 else { return 0 }
        return Double(freePageCount) / Double(pageCount) * 100.0
    }

    // MARK: Journal / WAL

    /// Current journal mode (PRAGMA journal_mode): "delete", "wal", "memory", etc.
    let journalMode: String

    /// Whether a WAL file was detected alongside the database file.
    let walFile: Bool

    /// Number of pages in the WAL at the time of a passive checkpoint, if available.
    let walPages: Int?

    // MARK: Configuration

    /// Auto-vacuum mode (PRAGMA auto_vacuum).
    let autoVacuum: AutoVacuumMode

    /// Database text encoding (PRAGMA encoding): "UTF-8", "UTF-16le", etc.
    let encoding: String

    /// Whether foreign-key enforcement is currently active (PRAGMA foreign_keys).
    let foreignKeysEnabled: Bool

    /// Suggested cache size in pages (PRAGMA cache_size).
    let cacheSize: Int

    /// Memory-mapped I/O limit in bytes (PRAGMA mmap_size).
    let mmapSize: Int64

    // MARK: Schema statistics

    /// Number of user-defined tables.
    let tableCount: Int

    /// Number of user-defined indexes.
    let indexCount: Int

    /// Number of user-defined views.
    let viewCount: Int

    /// Number of user-defined triggers.
    let triggerCount: Int

    // MARK: - AutoVacuumMode

    enum AutoVacuumMode: Int, Sendable {
        case none = 0
        case full = 1
        case incremental = 2

        /// Human-readable label for display in the health dashboard.
        var displayName: String {
            switch self {
            case .none:        return "None"
            case .full:        return "Full"
            case .incremental: return "Incremental"
            }
        }
    }
}

// MARK: - IntegrityCheckResult

/// Result of a PRAGMA integrity_check or PRAGMA quick_check operation.
struct IntegrityCheckResult: Sendable {
    /// `true` when the only message returned was "ok".
    let isOK: Bool

    /// All messages returned by the PRAGMA. Contains "ok" on success, error strings on failure.
    let messages: [String]

    /// Wall-clock duration of the check.
    let duration: TimeInterval
}
