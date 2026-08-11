//
//  SQLiteRowOperations.swift
//  PostgresGUI
//
//  Parameterized CRUD operations for SQLite tables.
//  All user-supplied identifiers are quoted; all user-supplied values
//  are passed as GRDB arguments — never interpolated into SQL strings.
//

import Foundation
import GRDB

// MARK: - SQLiteRowOperations

struct SQLiteRowOperations {

    // MARK: - UPDATE

    /// Build and execute a parameterized UPDATE statement.
    ///
    /// The row is identified using `primaryKeyColumns` matched against `originalRow.values`.
    /// Only columns present in `updatedValues` are included in the SET clause.
    ///
    /// - Returns: The number of rows affected (should be 1 for a well-formed PK).
    /// - Throws: `RowOperationError.noPrimaryKey` when `primaryKeyColumns` is empty.
    ///           `FileOpenError.unknownError` when a PK value is missing from `originalRow`.
    static func updateRow(
        db: Database,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) throws -> Int {
        let resolvedPKCols = try resolvePrimaryKeyColumns(
            db: db,
            table: table,
            candidatePKCols: primaryKeyColumns
        )

        guard !updatedValues.isEmpty else { return 0 }

        // Build SET clause: col1 = ?, col2 = ?
        let setCols = updatedValues.keys.sorted()
        let setClause = setCols
            .map { "\($0.quotedDatabaseIdentifier) = ?" }
            .joined(separator: ", ")

        // Build WHERE clause: pk1 = ? AND pk2 = ?
        let whereClause = try buildWhereClause(primaryKeyColumns: resolvedPKCols)

        let sql = """
            UPDATE \(table.quotedDatabaseIdentifier) \
            SET \(setClause) \
            WHERE \(whereClause)
            """

        // Collect SET arguments
        var args: [DatabaseValueConvertible?] = setCols.map { col in
            databaseValue(for: updatedValues[col]!)
        }

        // Collect WHERE arguments from original row values
        let whereArgs = try primaryKeyArguments(
            from: originalRow,
            keyColumns: resolvedPKCols,
            context: "UPDATE"
        )
        args.append(contentsOf: whereArgs)

        try db.execute(sql: sql, arguments: StatementArguments(args))
        return db.changesCount
    }

    // MARK: - DELETE

    /// Build and execute parameterized DELETE statements for multiple rows.
    ///
    /// All deletes run inside the single write transaction that GRDB's `queue.write` block
    /// already provides — no nested transaction is needed here.
    ///
    /// - Returns: Total number of rows deleted across all input rows.
    /// - Throws: `RowOperationError.noPrimaryKey` when `primaryKeyColumns` is empty.
    static func deleteRows(
        db: Database,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) throws -> Int {
        guard !rows.isEmpty else { return 0 }

        let resolvedPKCols = try resolvePrimaryKeyColumns(
            db: db,
            table: table,
            candidatePKCols: primaryKeyColumns
        )

        let whereClause = try buildWhereClause(primaryKeyColumns: resolvedPKCols)
        let sql = "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE \(whereClause)"

        var totalAffected = 0
        for row in rows {
            let args = try primaryKeyArguments(
                from: row,
                keyColumns: resolvedPKCols,
                context: "DELETE"
            )
            try db.execute(sql: sql, arguments: StatementArguments(args))
            totalAffected += db.changesCount
        }
        return totalAffected
    }

    // MARK: - INSERT

    /// Build and execute a parameterized INSERT statement.
    ///
    /// Columns with `.null` values are included explicitly (INSERT … NULL),
    /// allowing the caller to distinguish "omit" from "set NULL".
    /// Columns not present in `values` are omitted entirely so SQLite
    /// can apply DEFAULT or AUTOINCREMENT as declared.
    ///
    /// - Returns: The number of rows inserted (normally 1).
    static func insertRow(
        db: Database,
        table: String,
        values: [String: RowEditValue]
    ) throws -> Int {
        guard !values.isEmpty else {
            // INSERT INTO "t" DEFAULT VALUES — no columns provided
            let sql = "INSERT INTO \(table.quotedDatabaseIdentifier) DEFAULT VALUES"
            try db.execute(sql: sql)
            return db.changesCount
        }

        let cols = values.keys.sorted()
        let colList = cols
            .map { $0.quotedDatabaseIdentifier }
            .joined(separator: ", ")
        let placeholders = cols.map { _ in "?" }.joined(separator: ", ")

        let sql = """
            INSERT INTO \(table.quotedDatabaseIdentifier) \
            (\(colList)) \
            VALUES (\(placeholders))
            """

        let args: [DatabaseValueConvertible?] = cols.map { col in
            databaseValue(for: values[col]!)
        }

        try db.execute(sql: sql, arguments: StatementArguments(args))
        return db.changesCount
    }

    // MARK: - Private Helpers

    /// Resolve the effective primary key columns, falling back to `rowid` for
    /// rowid tables with no explicit PK, and throwing for WITHOUT ROWID tables
    /// with no declared PK.
    private static func resolvePrimaryKeyColumns(
        db: Database,
        table: String,
        candidatePKCols: [String]
    ) throws -> [String] {
        if !candidatePKCols.isEmpty {
            return candidatePKCols
        }

        // No explicit PK was provided — probe the table for a rowid alias.
        // WITHOUT ROWID tables have no implicit rowid; detect them via sqlite_schema.
        let isWithoutRowid = try checkIsWithoutRowid(db: db, table: table)
        if isWithoutRowid {
            throw RowOperationError.noPrimaryKey
        }

        // Regular rowid table: use "rowid" as the implicit key.
        return ["rowid"]
    }

    /// Returns true when the CREATE TABLE DDL for `table` contains WITHOUT ROWID.
    private static func checkIsWithoutRowid(db: Database, table: String) throws -> Bool {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT sql FROM sqlite_schema WHERE name = ? AND type = 'table'",
            arguments: [table]
        )
        guard let sql: String = row?["sql"] else { return false }
        return sql.uppercased().contains("WITHOUT ROWID")
    }

    /// Build a WHERE clause string like `"pk1" = ? AND "pk2" = ?`.
    private static func buildWhereClause(primaryKeyColumns: [String]) throws -> String {
        guard !primaryKeyColumns.isEmpty else {
            throw RowOperationError.noPrimaryKey
        }
        return primaryKeyColumns
            .map { "\($0.quotedDatabaseIdentifier) = ?" }
            .joined(separator: " AND ")
    }

    /// Extract primary key argument values from a `TableRow`.
    ///
    /// `TableRow.values` stores everything as `String?`; NULL is represented as `nil`.
    private static func primaryKeyArguments(
        from row: TableRow,
        keyColumns: [String],
        context: String
    ) throws -> [DatabaseValueConvertible?] {
        var args: [DatabaseValueConvertible?] = []
        for col in keyColumns {
            guard row.values.keys.contains(col) else {
                throw FileOpenError.unknownError(
                    "\(context): primary key column '\(col)' not found in row data."
                )
            }
            // row.values[col] is String?? — outer Optional is "key present", inner is the value.
            let rawValue: String?? = row.values[col]
            if let inner = rawValue, let str = inner {
                args.append(str as DatabaseValueConvertible)
            } else {
                args.append(nil)  // NULL primary key
            }
        }
        return args
    }

    /// Convert a `RowEditValue` to a GRDB-compatible optional.
    private static func databaseValue(for editValue: RowEditValue) -> DatabaseValueConvertible? {
        switch editValue {
        case .null:
            return nil
        case .value(let str):
            return str as DatabaseValueConvertible
        }
    }
}
