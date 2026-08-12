//
//  DestructiveSQLDetector.swift
//  PostgresGUI
//
//  Best-effort UX classification of SQL danger level.
//  This is NOT a security boundary — it is advisory UX only.
//

import Foundation

// MARK: - Danger Level

/// Relative danger level for a SQL statement.
/// Comparable so callers can do `level >= .dangerous`.
enum QueryDangerLevel: Int, Comparable {
    case safe        = 0  // SELECT, EXPLAIN, PRAGMA (read-only)
    case caution     = 1  // INSERT, CREATE, ALTER; UPDATE/DELETE with WHERE
    case dangerous   = 2  // DELETE/UPDATE without WHERE, VACUUM
    case destructive = 3  // DROP TABLE/INDEX/TRIGGER/VIEW

    static func < (lhs: QueryDangerLevel, rhs: QueryDangerLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Detector

struct DestructiveSQLDetector {

    // MARK: - Public API

    /// Classify a SQL statement's danger level.
    static func classify(_ sql: String) -> QueryDangerLevel {
        let normalized = normalize(sql)

        // Destructive: DROP object types
        if matchesDropDestructive(normalized) { return .destructive }

        // Dangerous: VACUUM
        if matchesVacuum(normalized) { return .dangerous }

        // Dangerous: DELETE/UPDATE without a WHERE clause
        if matchesDeleteWithoutWhere(normalized) { return .dangerous }
        if matchesUpdateWithoutWhere(normalized) { return .dangerous }

        // Safe: SELECT, EXPLAIN, PRAGMA
        if matchesSafe(normalized) { return .safe }

        // Caution: INSERT, CREATE, ALTER, DELETE with WHERE, UPDATE with WHERE
        if matchesCaution(normalized) { return .caution }

        // Everything else: treat as safe (ATTACH, DETACH, etc.)
        return .safe
    }

    /// Generate a human-readable warning message for the given SQL.
    /// Returns nil when no warning is needed.
    static func warningMessage(for sql: String) -> String? {
        let level = classify(sql)
        guard level >= .dangerous else { return nil }

        let normalized = normalize(sql)
        let table = extractTargetName(from: sql) ?? "the table"

        if matchesDropDestructive(normalized) {
            let objectType = extractDropObjectType(normalized) ?? "object"
            let label = objectType.capitalized
            return "This will permanently delete \(label) \"\(table)\" and all associated data. This cannot be undone."
        }

        if matchesVacuum(normalized) {
            return "VACUUM will rebuild the database file, requiring exclusive access. All other connections will be blocked until it completes."
        }

        if matchesDeleteWithoutWhere(normalized) {
            return "This will delete ALL rows from \"\(table)\". Are you sure?"
        }

        if matchesUpdateWithoutWhere(normalized) {
            return "This will update ALL rows in \"\(table)\". Are you sure?"
        }

        return nil
    }

    // MARK: - Classification Helpers

    private static func matchesSafe(_ normalized: String) -> Bool {
        normalized.hasPrefix("SELECT") ||
        normalized.hasPrefix("EXPLAIN") ||
        normalized.hasPrefix("PRAGMA") ||
        normalized.hasPrefix("WITH")
    }

    private static func matchesCaution(_ normalized: String) -> Bool {
        normalized.hasPrefix("INSERT") ||
        normalized.hasPrefix("CREATE") ||
        normalized.hasPrefix("ALTER")  ||
        matchesDeleteWithWhere(normalized) ||
        matchesUpdateWithWhere(normalized)
    }

    private static func matchesVacuum(_ normalized: String) -> Bool {
        hasPrefix(normalized, pattern: #"^VACUUM(\s|$)"#)
    }

    // DROP TABLE / INDEX / TRIGGER / VIEW
    private static func matchesDropDestructive(_ normalized: String) -> Bool {
        hasPrefix(normalized, pattern: #"^DROP\s+(TABLE|INDEX|TRIGGER|VIEW)\b"#)
    }

    // DELETE without WHERE — heuristic: no \bWHERE\b after the verb
    private static func matchesDeleteWithoutWhere(_ normalized: String) -> Bool {
        guard hasPrefix(normalized, pattern: #"^DELETE\s+FROM\b"#) else { return false }
        return !hasWhere(normalized)
    }

    private static func matchesDeleteWithWhere(_ normalized: String) -> Bool {
        guard hasPrefix(normalized, pattern: #"^DELETE\s+FROM\b"#) else { return false }
        return hasWhere(normalized)
    }

    // UPDATE without WHERE
    private static func matchesUpdateWithoutWhere(_ normalized: String) -> Bool {
        guard hasPrefix(normalized, pattern: #"^UPDATE\b"#) else { return false }
        return !hasWhere(normalized)
    }

    private static func matchesUpdateWithWhere(_ normalized: String) -> Bool {
        guard hasPrefix(normalized, pattern: #"^UPDATE\b"#) else { return false }
        return hasWhere(normalized)
    }

    // MARK: - Regex Utilities

    private static func hasPrefix(_ normalized: String, pattern: String) -> Bool {
        normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private static func hasWhere(_ normalized: String) -> Bool {
        normalized.range(of: #"\bWHERE\b"#, options: .regularExpression) != nil
    }

    // MARK: - Name Extraction

    private static func extractDropObjectType(_ normalized: String) -> String? {
        let pattern = #"^DROP\s+(TABLE|INDEX|TRIGGER|VIEW)\b"#
        guard let match = normalized.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = String(normalized[match])
        let parts = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.count >= 2 ? parts[1].lowercased() : nil
    }

    private static func extractTargetName(from sql: String) -> String? {
        let t = sql.trimmingCharacters(in: .whitespacesAndNewlines)

        // DROP TABLE [IF EXISTS] name
        if let n = extract(from: t, pattern: #"(?i)DROP\s+(?:TABLE|INDEX|TRIGGER|VIEW)\s+(?:IF\s+EXISTS\s+)?([\w"`.]+)"#) {
            return clean(n)
        }
        // DELETE FROM name
        if let n = extract(from: t, pattern: #"(?i)DELETE\s+FROM\s+([\w"`.]+)"#) {
            return clean(n)
        }
        // UPDATE name
        if let n = extract(from: t, pattern: #"(?i)UPDATE\s+([\w"`.]+)"#) {
            return clean(n)
        }
        return nil
    }

    private static func extract(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2 else { return nil }
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "`", with: "")
            .components(separatedBy: ".").last ?? name
    }

    // MARK: - Normalization

    private static func normalize(_ sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
