//
//  SchemaRelationshipService.swift
//  Tarn
//
//  Stateless service that queries SQLite foreign-key metadata and
//  assembles a SchemaOverview from pragma_foreign_key_list.
//  All methods run synchronously inside a GRDB Database block.
//

import Foundation
import GRDB

// MARK: - SchemaRelationshipService

struct SchemaRelationshipService {

    // MARK: - Public API

    /// Build a complete SchemaOverview for the given database connection.
    ///
    /// - Parameter db: An open GRDB `Database` (read access is sufficient).
    /// - Returns: A `SchemaOverview` with all tables and FK relationships.
    static func fetchOverview(db: Database) throws -> SchemaOverview {
        let relationships = try fetchRelationships(db: db)
        let tables        = try fetchTables(db: db)
        return SchemaOverview(tables: tables, relationships: relationships)
    }

    // MARK: - Relationships

    /// Fetch all foreign-key relationships across all user tables.
    ///
    /// Uses `pragma_foreign_key_list` as a table-valued function so it can
    /// be joined against `sqlite_schema` in a single query — no need to
    /// loop and call PRAGMA per table.
    static func fetchRelationships(db: Database) throws -> [SchemaRelationship] {
        // sqlite_schema has type='table' for user tables.
        // pragma_foreign_key_list(m.name) returns one row per FK column:
        //   id, seq, "table", "from", "to", on_update, on_delete, match
        let sql = """
            SELECT
                m.name          AS source_table,
                p."from"        AS source_column,
                p."table"       AS target_table,
                p."to"          AS target_column
            FROM sqlite_schema AS m
            JOIN pragma_foreign_key_list(m.name) AS p
            WHERE m.type = 'table'
            ORDER BY m.name, p.id, p.seq
        """

        let rows = try Row.fetchAll(db, sql: sql)
        return rows.compactMap { row -> SchemaRelationship? in
            guard
                let source: String = row["source_table"],
                let srcCol: String = row["source_column"],
                let target: String = row["target_table"],
                let tgtCol: String = row["target_column"]
            else { return nil }
            return SchemaRelationship(
                sourceTable:  source,
                sourceColumn: srcCol,
                targetTable:  target,
                targetColumn: tgtCol
            )
        }
    }

    // MARK: - Tables

    /// Fetch metadata for every user table: name, primary keys, column count, row count.
    ///
    /// Row counts are fetched with a best-effort approach: if `SELECT COUNT(*)`
    /// fails for a table (e.g. virtual table), `rowCount` is `nil`.
    static func fetchTables(db: Database) throws -> [SchemaTable] {
        // Retrieve table names from sqlite_schema (excludes SQLite internals).
        let tableNames: [String] = try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_schema
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                ORDER BY name
            """
        )

        return try tableNames.map { name in
            let primaryKeys  = try fetchPrimaryKeys(db: db, table: name)
            let columnCount  = try fetchColumnCount(db: db, table: name)
            let rowCount     = try? fetchRowCount(db: db, table: name)
            return SchemaTable(
                name:        name,
                primaryKeys: primaryKeys,
                columnCount: columnCount,
                rowCount:    rowCount
            )
        }
    }

    // MARK: - Private Helpers

    private static func fetchPrimaryKeys(db: Database, table: String) throws -> [String] {
        // pragma_table_info returns one row per column; pk > 0 means it's part of the PK.
        // pk value is the 1-based position within a composite key.
        let sql = """
            SELECT name FROM pragma_table_info(?)
            WHERE pk > 0
            ORDER BY pk
        """
        return try String.fetchAll(db, sql: sql, arguments: [table])
    }

    private static func fetchColumnCount(db: Database, table: String) throws -> Int {
        let sql = "SELECT COUNT(*) FROM pragma_table_info(?)"
        return try Int.fetchOne(db, sql: sql, arguments: [table]) ?? 0
    }

    private static func fetchRowCount(db: Database, table: String) throws -> Int64 {
        // Table name cannot be parameterized in SQLite identifiers — quote it safely.
        let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
        let sql    = "SELECT COUNT(*) FROM \"\(quoted)\""
        return try Int64.fetchOne(db, sql: sql) ?? 0
    }
}
