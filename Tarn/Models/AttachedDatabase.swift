//
//  AttachedDatabase.swift
//  Tarn
//
//  Represents a database attached to the current SQLite connection.
//  SQLite always has at least "main" (the primary file) and "temp" (transient).
//

import Foundation

// MARK: - AttachedDatabase

struct AttachedDatabase: Identifiable, Equatable {
    /// Stable identity — the alias is unique per connection.
    var id: String { alias }

    /// The sequence number returned by PRAGMA database_list (informational only).
    let seq: Int

    /// The alias used to reference this database in SQL (e.g. `SELECT * FROM logs.events`).
    let alias: String

    /// Absolute path to the file on disk, or empty string for in-memory / temp databases.
    let filePath: String

    /// True when this entry is the primary database ("main").
    var isMain: Bool { alias == "main" }

    /// True when this entry is SQLite's built-in temporary database ("temp").
    var isTemp: Bool { alias == "temp" }

    /// True when the alias is reserved and cannot be detached.
    var isReserved: Bool { isMain || isTemp }

    /// Display name shown in the UI — uses the last path component when a path is available.
    var displayFileName: String {
        guard !filePath.isEmpty else {
            return isTemp ? "(temporary)" : "(in-memory)"
        }
        return (filePath as NSString).lastPathComponent
    }
}
