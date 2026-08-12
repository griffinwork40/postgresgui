//
//  SQLiteValue.swift
//  Tarn
//
//  Database-neutral typed value representation for SQLite query results.
//  Values remain typed through the query/service layer; string conversion
//  happens only at presentation/export boundaries.
//

import Foundation

// MARK: - Typed Value

/// A single database value preserving its SQLite storage class.
/// Covers the five fundamental SQLite storage classes: NULL, INTEGER, REAL, TEXT, BLOB.
enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

// MARK: - Result Column

/// Metadata for a single column in a query result set.
/// Preserves column order and allows duplicate column names.
struct ResultColumn: Sendable, Equatable {
    /// Column name as returned by the query (may duplicate another column's name).
    let name: String

    /// Declared type from table schema metadata, if available.
    /// Nil for computed expressions, aggregates, or when the type is unknown.
    let declaredType: String?

    init(name: String, declaredType: String? = nil) {
        self.name = name
        self.declaredType = declaredType
    }
}

// MARK: - Result Row

/// A single row from a query result.
/// Values are positional (indexed by column position), not keyed by name.
/// This preserves duplicate column names and column order.
struct ResultRow: Identifiable, Sendable {
    let id: UUID
    let values: [SQLiteValue]

    init(id: UUID = UUID(), values: [SQLiteValue]) {
        self.id = id
        self.values = values
    }

    /// Access a value by column index.
    subscript(index: Int) -> SQLiteValue {
        values[index]
    }
}

// MARK: - Typed Query Result

/// Complete typed query result set.
/// Columns and rows are ordered; column names may contain duplicates.
struct TypedQueryResult: Sendable {
    /// Ordered column metadata. `columns.count == row.values.count` for every row.
    let columns: [ResultColumn]

    /// Result rows in query order.
    let rows: [ResultRow]

    /// Wall-clock query execution time.
    let executionTime: TimeInterval

    /// Number of rows affected by INSERT/UPDATE/DELETE. Nil for SELECT.
    let affectedRows: Int?

    /// Error from a failed query. Nil on success.
    let error: Error?

    /// Convenience: was the query successful?
    var isSuccess: Bool { error == nil }

    /// Ordered column names (convenience for display).
    var columnNames: [String] { columns.map(\.name) }

    // MARK: - Factories

    static func success(
        columns: [ResultColumn],
        rows: [ResultRow],
        executionTime: TimeInterval,
        affectedRows: Int? = nil
    ) -> TypedQueryResult {
        TypedQueryResult(
            columns: columns,
            rows: rows,
            executionTime: executionTime,
            affectedRows: affectedRows,
            error: nil
        )
    }

    static func failure(error: Error, executionTime: TimeInterval) -> TypedQueryResult {
        TypedQueryResult(
            columns: [],
            rows: [],
            executionTime: executionTime,
            affectedRows: nil,
            error: error
        )
    }
}

// MARK: - Presentation Conversion

extension SQLiteValue {
    /// Convert to a display string for the UI. This is the presentation boundary.
    var displayString: String? {
        switch self {
        case .null:
            return nil
        case .integer(let v):
            return String(v)
        case .real(let v):
            return String(v)
        case .text(let v):
            return v
        case .blob(let data):
            return "[BLOB: \(data.count) bytes]"
        }
    }

    /// Human-readable storage class name.
    var storageClassName: String {
        switch self {
        case .null: return "NULL"
        case .integer: return "INTEGER"
        case .real: return "REAL"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        }
    }
}

extension ResultRow {
    /// Convert a typed result row to the legacy `TableRow` display model.
    /// This is the presentation boundary — use only in views and export code.
    func toDisplayRow(columns: [ResultColumn]) -> TableRow {
        var dict: [String: String?] = [:]
        for (index, column) in columns.enumerated() where index < values.count {
            // For duplicate column names, later columns overwrite earlier ones in the dict.
            // The positional TypedQueryResult preserves both; the dict-based TableRow cannot.
            dict[column.name] = values[index].displayString
        }
        return TableRow(id: id, values: dict)
    }
}

extension TypedQueryResult {
    /// Convert the entire result set to legacy display format.
    /// Use only at the presentation boundary.
    func toDisplayRows() -> [TableRow] {
        rows.map { $0.toDisplayRow(columns: columns) }
    }

    /// Convert to the legacy QueryResult type for compatibility with existing UI code.
    func toQueryResult() -> QueryResult {
        if let error = error {
            return .failure(error: error, executionTime: executionTime)
        }
        return .success(
            rows: toDisplayRows(),
            columnNames: columnNames,
            executionTime: executionTime
        )
    }
}
