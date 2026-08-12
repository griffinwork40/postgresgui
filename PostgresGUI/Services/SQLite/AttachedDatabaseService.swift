//
//  AttachedDatabaseService.swift
//  PostgresGUI
//
//  Stateless service for managing SQLite attached databases.
//  All methods accept an open GRDB Database and run inline — call them
//  from within a DatabaseQueue.read / .write / .inTransaction block.
//
//  SQLite ATTACH semantics:
//  - "main" and "temp" are always present and cannot be detached.
//  - ATTACH persists only for the lifetime of the current connection.
//  - The alias must be a valid SQL identifier.
//

import Foundation
import GRDB

// MARK: - AttachedDatabaseService

struct AttachedDatabaseService {

    // MARK: - Attach

    /// Attach an external SQLite file under the given alias.
    ///
    /// - Parameters:
    ///   - db:       Open GRDB `Database` (write access required).
    ///   - filePath: Absolute path to the database file to attach.
    ///   - alias:    SQL identifier used to reference the attached database.
    /// - Throws: `AttachedDatabaseError.reservedAlias` for "main" or "temp";
    ///           `AttachedDatabaseError.invalidAlias` for non-identifier strings;
    ///           GRDB/SQLite errors on I/O or permission failures.
    static func attachDatabase(
        db: Database,
        filePath: String,
        alias: String
    ) throws {
        try validateAlias(alias)
        // ATTACH DATABASE uses positional bindings for both path and alias.
        // The alias is embedded directly as a quoted identifier — binding it
        // as a parameter is not supported by SQLite syntax.
        let quotedAlias = alias.quotedDatabaseIdentifier
        try db.execute(
            sql: "ATTACH DATABASE ? AS \(quotedAlias)",
            arguments: [filePath]
        )
        DebugLog.print("Attached database at '\(filePath)' as \(quotedAlias)")
    }

    // MARK: - Detach

    /// Detach a previously attached database by alias.
    ///
    /// - Parameters:
    ///   - db:    Open GRDB `Database` (write access required).
    ///   - alias: The alias to detach. Must not be "main" or "temp".
    /// - Throws: `AttachedDatabaseError.reservedAlias` for protected aliases;
    ///           `AttachedDatabaseError.invalidAlias` for non-identifier strings;
    ///           GRDB/SQLite errors if the alias is not attached.
    static func detachDatabase(db: Database, alias: String) throws {
        try validateAlias(alias)
        let quotedAlias = alias.quotedDatabaseIdentifier
        try db.execute(sql: "DETACH DATABASE \(quotedAlias)")
        DebugLog.print("Detached database alias \(quotedAlias)")
    }

    // MARK: - List

    /// Query `PRAGMA database_list` and return all currently attached databases.
    ///
    /// "main" and "temp" are always present. The result is ordered by `seq`.
    ///
    /// - Parameter db: Open GRDB `Database` (read access is sufficient).
    /// - Returns: All attached databases, including "main" and "temp".
    static func listAttachedDatabases(db: Database) throws -> [AttachedDatabase] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA database_list")
        return rows.compactMap { row -> AttachedDatabase? in
            guard
                let seq:   Int    = row["seq"],
                let name:  String = row["name"],
                let file:  String = row["file"]
            else { return nil }
            return AttachedDatabase(seq: seq, alias: name, filePath: file)
        }
        .sorted { $0.seq < $1.seq }
    }

    // MARK: - Tables for Attached Database

    /// Fetch table and view names from the given attached database's schema.
    ///
    /// Uses `[alias].sqlite_schema` to list objects only in that attached database.
    /// The returned `TableInfo` values use `alias` as the `schema` field so that
    /// callers can build qualified names like `alias.table_name`.
    ///
    /// - Parameters:
    ///   - db:    Open GRDB `Database` (read access is sufficient).
    ///   - alias: The attached database alias to inspect.
    /// - Returns: Tables and views in that database, excluding SQLite internals.
    static func fetchTablesForAttached(
        db: Database,
        alias: String
    ) throws -> [TableInfo] {
        let quotedAlias = alias.quotedDatabaseIdentifier
        let sql = """
            SELECT name, type
            FROM \(quotedAlias).sqlite_schema
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
            ORDER BY type DESC, name ASC
        """
        let rows = try Row.fetchAll(db, sql: sql)
        return rows.compactMap { row -> TableInfo? in
            guard
                let name: String = row["name"],
                let type: String = row["type"]
            else { return nil }
            let tableType: TableType = type == "view" ? .view : .regular
            return TableInfo(name: name, schema: alias, tableType: tableType)
        }
    }

    // MARK: - Alias Validation

    /// Validate that `alias` is a usable SQL identifier and not a reserved name.
    ///
    /// - Throws: `AttachedDatabaseError.reservedAlias` or `.invalidAlias`.
    static func validateAlias(_ alias: String) throws {
        guard !alias.isEmpty else {
            throw AttachedDatabaseError.invalidAlias("Alias must not be empty.")
        }
        let reserved = ["main", "temp"]
        if reserved.contains(alias.lowercased()) {
            throw AttachedDatabaseError.reservedAlias(alias)
        }
        // Must start with letter or underscore; subsequent chars may be alphanumeric or '_'.
        let identifierPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        guard alias.range(of: identifierPattern, options: .regularExpression) != nil else {
            throw AttachedDatabaseError.invalidAlias(
                "'\(alias)' is not a valid SQL identifier. Use letters, digits, and underscores only."
            )
        }
    }
}

// MARK: - AttachedDatabaseError

enum AttachedDatabaseError: LocalizedError, Equatable {
    case reservedAlias(String)
    case invalidAlias(String)

    var errorDescription: String? {
        switch self {
        case .reservedAlias(let alias):
            return "'\(alias)' is a reserved alias and cannot be attached or detached."
        case .invalidAlias(let message):
            return message
        }
    }
}
