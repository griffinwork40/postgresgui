//
//  SQLiteDatabaseService+Attached.swift
//  PostgresGUI
//
//  SQLiteDatabaseService extension for attached-database operations (Phase 6e).
//  Thin async wrappers that delegate to AttachedDatabaseService inside GRDB blocks.
//

import Foundation
import GRDB

extension SQLiteDatabaseService {

    // MARK: - Attached Databases

    /// Attach an external SQLite file under the given alias.
    ///
    /// Validation (reserved alias, identifier rules) is performed by
    /// `AttachedDatabaseService.validateAlias` before the SQL is executed.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the database file on disk.
    ///   - alias:    SQL identifier for the new attachment (e.g. "logs").
    func attachDatabase(filePath: String, alias: String) async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        try await connectionManager.withDatabaseWrite { db in
            try AttachedDatabaseService.attachDatabase(db: db, filePath: filePath, alias: alias)
        }
    }

    /// Detach a previously attached database by alias.
    ///
    /// - Parameter alias: The alias to detach. Must not be "main" or "temp".
    func detachDatabase(alias: String) async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        try await connectionManager.withDatabaseWrite { db in
            try AttachedDatabaseService.detachDatabase(db: db, alias: alias)
        }
    }

    /// List all currently attached databases (always includes "main" and "temp").
    ///
    /// Results are ordered by the `seq` column returned by `PRAGMA database_list`.
    func listAttachedDatabases() async throws -> [AttachedDatabase] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { db in
            try AttachedDatabaseService.listAttachedDatabases(db: db)
        }
    }

    /// Fetch tables and views from a specific attached database alias.
    ///
    /// The returned `TableInfo` values use `alias` as their `schema` property so
    /// callers can build qualified references like `alias.table_name`.
    ///
    /// - Parameter alias: The alias of the attached database to inspect.
    func fetchTablesForAttached(alias: String) async throws -> [TableInfo] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { db in
            try AttachedDatabaseService.fetchTablesForAttached(db: db, alias: alias)
        }
    }
}
