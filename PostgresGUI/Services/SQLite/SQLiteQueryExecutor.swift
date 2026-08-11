//
//  SQLiteQueryExecutor.swift
//  PostgresGUI
//
//  SQLite implementation of query execution.
//  Returns TypedQueryResult with values preserved as SQLiteValue (not strings).
//  Uses sqlite_schema (not the legacy sqlite_master alias).
//

import Foundation
import GRDB
import Logging

struct SQLiteQueryExecutor {

    private let logger = Logger.debugLogger(label: "com.sqlitegui.query")

    // MARK: - Table Discovery

    /// Fetch all user tables and views from sqlite_schema.
    func fetchTables(db: Database) throws -> [TableInfo] {
        let sql = """
            SELECT name, type, sql
            FROM sqlite_schema
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
            ORDER BY type DESC, name ASC
        """

        var tables: [TableInfo] = []
        let rows = try Row.fetchAll(db, sql: sql)

        for row in rows {
            let name: String = row["name"]
            let type: String = row["type"]
            let createSQL: String? = row["sql"]

            // Detect virtual tables (FTS, etc.) from CREATE VIRTUAL TABLE statement
            let isVirtual = createSQL?.uppercased().hasPrefix("CREATE VIRTUAL TABLE") ?? false
            let tableType: TableType = isVirtual ? .regular : (type == "view" ? .regular : .regular)

            // Use "main" as the schema for SQLite's default database
            tables.append(TableInfo(
                name: name,
                schema: "main",
                tableType: tableType
            ))
        }

        logger.info("Fetched \(tables.count) tables/views")
        return tables
    }

    // MARK: - Column Metadata

    /// Fetch column info using PRAGMA table_xinfo (includes generated columns).
    func fetchColumns(db: Database, table: String) throws -> [ColumnInfo] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_xinfo(\(table.quotedDatabaseIdentifier))")
        var columns: [ColumnInfo] = []

        for row in rows {
            let name: String = row["name"]
            let declaredType: String = row["type"] ?? ""
            let notNull: Bool = row["notnull"] == 1
            let defaultValue: String? = row["dflt_value"]
            let pkIndex: Int = row["pk"]
            let hidden: Int = row["hidden"]  // 0=normal, 1=virtual generated, 2=stored generated

            // Skip hidden/generated columns that shouldn't appear in normal column listings
            // hidden=1 is virtual generated, hidden=2 is stored generated, hidden=3 is __hidden__
            let _ = hidden  // Keep the info but include all columns for now

            columns.append(ColumnInfo(
                name: name,
                dataType: declaredType.isEmpty ? "ANY" : declaredType,
                isNullable: !notNull,
                defaultValue: defaultValue,
                isPrimaryKey: pkIndex > 0
            ))
        }

        logger.info("Fetched \(columns.count) columns for \(table)")
        return columns
    }

    /// Fetch primary key column names for a table.
    func fetchPrimaryKeys(db: Database, table: String) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.quotedDatabaseIdentifier))")
        var pkColumns: [(name: String, pkIndex: Int)] = []

        for row in rows {
            let pkIndex: Int = row["pk"]
            if pkIndex > 0 {
                let name: String = row["name"]
                pkColumns.append((name: name, pkIndex: pkIndex))
            }
        }

        // Sort by pk index (composite keys are ordered)
        pkColumns.sort { $0.pkIndex < $1.pkIndex }

        logger.info("Found \(pkColumns.count) primary key columns for \(table)")
        return pkColumns.map(\.name)
    }

    // MARK: - DDL

    /// Get the CREATE statement for a table directly from sqlite_schema.
    func generateDDL(db: Database, table: String) throws -> String {
        let row = try Row.fetchOne(db, sql: """
            SELECT sql FROM sqlite_schema
            WHERE name = ? AND type IN ('table', 'view')
        """, arguments: [table])

        guard let sql: String = row?["sql"] else {
            return "-- No DDL found for '\(table)'"
        }
        return sql + ";"
    }

    // MARK: - Data Fetching (Typed)

    /// Fetch a page of rows from a table, returning typed results.
    /// Uses LIMIT/OFFSET pagination (MVP strategy; keyset pagination is a future improvement).
    func fetchTableData(
        db: Database,
        table: String,
        limit: Int,
        offset: Int
    ) throws -> TypedQueryResult {
        let startTime = Date()
        let sql = "SELECT * FROM \(table.quotedDatabaseIdentifier) LIMIT \(limit) OFFSET \(offset)"
        return try executeSelect(db: db, sql: sql, startTime: startTime)
    }

    // MARK: - Arbitrary Query Execution

    /// Execute arbitrary SQL and return typed results.
    /// For SELECT statements, returns full result set.
    /// For non-SELECT, returns affected row count.
    func executeQuery(db: Database, sql: String) throws -> TypedQueryResult {
        let startTime = Date()

        // Use GRDB's statement compilation to detect statement type
        let statement = try db.makeStatement(sql: sql)

        if statement.isReadonly {
            return try executeSelect(db: db, sql: sql, startTime: startTime)
        } else {
            // Write statement
            try db.execute(sql: sql)
            let changes = db.changesCount
            let duration = Date().timeIntervalSince(startTime)
            return TypedQueryResult.success(
                columns: [],
                rows: [],
                executionTime: duration,
                affectedRows: changes
            )
        }
    }

    // MARK: - Private Helpers

    /// Execute a SELECT and map results to TypedQueryResult with SQLiteValue preservation.
    private func executeSelect(db: Database, sql: String, startTime: Date) throws -> TypedQueryResult {
        let statement = try db.makeStatement(sql: sql)
        let columnCount = statement.columnCount

        // Build column metadata
        var columns: [ResultColumn] = []
        for i in 0..<columnCount {
            columns.append(ResultColumn(
                name: statement.columnNames[i],
                declaredType: nil  // GRDB doesn't expose declared types from statement; can be fetched separately
            ))
        }

        // Iterate rows, preserving SQLite storage classes
        let cursor = try Row.fetchCursor(statement)
        var resultRows: [ResultRow] = []

        while let row = try cursor.next() {
            var values: [SQLiteValue] = []
            values.reserveCapacity(columnCount)

            for i in 0..<columnCount {
                let dbValue = row[i] as DatabaseValue
                values.append(dbValue.toSQLiteValue())
            }

            resultRows.append(ResultRow(values: values))
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.info("SELECT returned \(resultRows.count) rows in \(String(format: "%.3f", duration))s")

        return TypedQueryResult.success(
            columns: columns,
            rows: resultRows,
            executionTime: duration
        )
    }
}

// MARK: - GRDB DatabaseValue → SQLiteValue Bridge

extension DatabaseValue {
    /// Convert GRDB's DatabaseValue to our typed SQLiteValue, preserving the storage class.
    func toSQLiteValue() -> SQLiteValue {
        switch storage {
        case .null:
            return .null
        case .int64(let value):
            return .integer(value)
        case .double(let value):
            return .real(value)
        case .string(let value):
            return .text(value)
        case .blob(let data):
            return .blob(data)
        }
    }
}
