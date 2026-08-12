//
//  FTSDetectionService.swift
//  PostgresGUI
//
//  Stateless service that detects FTS virtual tables in a SQLite database
//  and parses their CREATE VIRTUAL TABLE statements to extract metadata.
//  All methods take a GRDB `Database` parameter (read access is sufficient).
//

import Foundation
import GRDB

// MARK: - FTSDetectionService

struct FTSDetectionService {

    // MARK: - Table Discovery

    /// Fetch all FTS virtual tables from sqlite_schema and parse their metadata.
    ///
    /// - Parameter db: An open GRDB `Database` (read access is sufficient).
    /// - Returns: An array of `FTSTableInfo` values, one per FTS virtual table.
    static func fetchFTSTables(db: Database) throws -> [FTSTableInfo] {
        let sql = """
            SELECT name, sql
            FROM sqlite_schema
            WHERE type = 'table'
              AND sql LIKE 'CREATE VIRTUAL TABLE%USING fts%'
            ORDER BY name ASC
        """

        let rows = try Row.fetchAll(db, sql: sql)
        return rows.compactMap { row -> FTSTableInfo? in
            guard let name: String = row["name"],
                  let createSQL: String = row["sql"]
            else { return nil }
            return parse(name: name, createSQL: createSQL)
        }
    }

    // MARK: - MATCH Query Generation

    /// Build a MATCH query SQL string for the given FTS table and search term.
    ///
    /// For FTS5, the SELECT includes `rank` (from the built-in ranker) and
    /// a `bm25()` score column for display purposes.
    /// For FTS3/4, a plain MATCH is issued without rank columns.
    ///
    /// - Parameters:
    ///   - table:   The FTS table to search.
    ///   - query:   The FTS MATCH expression (e.g. "hello world").
    /// - Returns:   A SQL string with a single `?` placeholder for the query term.
    static func buildMatchSQL(table: FTSTableInfo, query: String) -> String {
        let quoted = table.name.quotedDatabaseIdentifier
        switch table.module {
        case .fts5:
            // FTS5: built-in `rank` column + explicit bm25() score
            return """
                SELECT *, rank AS fts_rank, bm25(\(quoted)) AS bm25_score
                FROM \(quoted)
                WHERE \(quoted) MATCH ?
                ORDER BY rank
            """
        case .fts3, .fts4:
            return """
                SELECT *
                FROM \(quoted)
                WHERE \(quoted) MATCH ?
            """
        }
    }

    // MARK: - SQL Parsing

    /// Parse a `CREATE VIRTUAL TABLE … USING ftsN(…)` statement and
    /// return a populated `FTSTableInfo`, or `nil` if parsing fails.
    static func parse(name: String, createSQL: String) -> FTSTableInfo? {
        let upper = createSQL.uppercased()

        // Detect module: fts5 before fts4/fts3 to avoid prefix-match confusion
        let module: FTSModule
        if upper.contains("USING FTS5") {
            module = .fts5
        } else if upper.contains("USING FTS4") {
            module = .fts4
        } else if upper.contains("USING FTS3") {
            module = .fts3
        } else {
            return nil
        }

        // Extract the argument list inside the outer parentheses
        // CREATE VIRTUAL TABLE foo USING ftsN( ... )
        guard let argsString = extractArgList(from: createSQL) else {
            return FTSTableInfo(
                id: name, name: name, module: module,
                tokenizer: nil, contentTable: nil, indexedColumns: []
            )
        }

        let args = splitArgs(argsString)
        var tokenizer: String?
        var contentTable: String?
        var indexedColumns: [String] = []

        for arg in args {
            let trimmed = arg.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("tokenize") {
                // e.g.  tokenize=porter  or  tokenize="porter"
                tokenizer = extractValue(from: trimmed)
            } else if lower.hasPrefix("content") {
                // e.g.  content=articles  or  content=""  (contentless)
                let val = extractValue(from: trimmed)
                contentTable = val?.isEmpty == false ? val : nil
            } else if !trimmed.isEmpty && !isKnownOption(lower) {
                // Anything that is not a recognised key=value option is a column name
                // Strip surrounding backticks/quotes if present
                let colName = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'[]"))
                if !colName.isEmpty {
                    indexedColumns.append(colName)
                }
            }
        }

        return FTSTableInfo(
            id: name,
            name: name,
            module: module,
            tokenizer: tokenizer,
            contentTable: contentTable,
            indexedColumns: indexedColumns
        )
    }

    // MARK: - Private Parsing Helpers

    /// Extracts the text inside the outermost parentheses of the CREATE statement.
    private static func extractArgList(from sql: String) -> String? {
        guard let open = sql.firstIndex(of: "("),
              let close = sql.lastIndex(of: ")")
        else { return nil }
        let start = sql.index(after: open)
        guard start < close else { return nil }
        return String(sql[start..<close])
    }

    /// Split a comma-separated argument list, respecting nested parentheses.
    private static func splitArgs(_ argsString: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0

        for ch in argsString {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")": depth -= 1; current.append(ch)
            case "," where depth == 0:
                result.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current)
        }
        return result
    }

    /// Extracts the value from a `key=value` pair, stripping surrounding quotes.
    private static func extractValue(from arg: String) -> String? {
        guard let eq = arg.firstIndex(of: "=") else { return nil }
        let valueStart = arg.index(after: eq)
        let raw = String(arg[valueStart...]).trimmingCharacters(in: .whitespaces)
        return raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Returns `true` for known FTS option keywords (key= pairs) that are not column names.
    private static func isKnownOption(_ lower: String) -> Bool {
        let knownPrefixes = [
            "content", "tokenize", "prefix", "compress", "uncompress",
            "matchinfo", "languageid", "order", "detail", "notindexed"
        ]
        return knownPrefixes.contains { lower.hasPrefix($0) }
    }
}
