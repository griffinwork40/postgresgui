//
//  QueryEditability.swift
//  Tarn
//

import Foundation

struct QueryEditabilityContext: Equatable {
    let query: String
    let sourceTable: String?
    let sourceSchema: String?
}

struct EditabilityReason: Equatable {
    let title: String
    let body: String
}

struct QueryEditability: Equatable {
    let isEditable: Bool
    let tableName: String?
    let schemaName: String?
    let disabledReason: EditabilityReason?

    static func editable(tableName: String, schemaName: String?) -> QueryEditability {
        QueryEditability(
            isEditable: true,
            tableName: tableName,
            schemaName: schemaName,
            disabledReason: nil
        )
    }

    static func notEditable(title: String, body: String) -> QueryEditability {
        QueryEditability(
            isEditable: false,
            tableName: nil,
            schemaName: nil,
            disabledReason: EditabilityReason(title: title, body: body)
        )
    }
}

func determineQueryEditability(_ context: QueryEditabilityContext) -> QueryEditability {
    // If we have an explicit source table (user clicked table in sidebar), it's editable
    if let table = context.sourceTable {
        return .editable(tableName: table, schemaName: context.sourceSchema)
    }

    // For manual queries, analyze the SQL
    return analyzeQueryForEditability(context.query)
}

private func analyzeQueryForEditability(_ query: String) -> QueryEditability {
    let normalized = query.uppercased()

    // Check for non-editable patterns
    if let reason = detectNonEditablePattern(normalized) {
        return .notEditable(title: reason.title, body: reason.body)
    }

    // Try to extract single table from simple SELECT
    if let (table, schema) = extractTableFromSelect(query) {
        return .editable(tableName: table, schemaName: schema)
    }

    // Couldn't determine table
    return .notEditable(
        title: "Can't Edit Query Results",
        body: "Row editing is only available when viewing a table directly. Select a table from the sidebar to edit its rows."
    )
}

private func detectNonEditablePattern(_ normalizedQuery: String) -> EditabilityReason? {
    // CTE (must check before other patterns since CTE contains SELECT)
    let trimmed = normalizedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("WITH ") {
        return EditabilityReason(
            title: "Can't Edit CTE Results",
            body: "This query uses a Common Table Expression (WITH clause). To edit rows, select a table from the sidebar."
        )
    }

    // JOINs
    let joinPatterns = [" JOIN ", " INNER JOIN ", " LEFT JOIN ", " RIGHT JOIN ", " FULL JOIN ", " CROSS JOIN "]
    for pattern in joinPatterns {
        if normalizedQuery.contains(pattern) {
            return EditabilityReason(
                title: "Can't Edit Joined Results",
                body: "This query combines data from multiple tables. To edit rows, select a single table from the sidebar."
            )
        }
    }

    // UNION/INTERSECT/EXCEPT
    if normalizedQuery.contains(" UNION ") || normalizedQuery.contains(" INTERSECT ") || normalizedQuery.contains(" EXCEPT ") {
        return EditabilityReason(
            title: "Can't Edit Combined Results",
            body: "This query combines multiple result sets. To edit rows, select a single table from the sidebar."
        )
    }

    // GROUP BY
    if normalizedQuery.contains(" GROUP BY ") {
        return EditabilityReason(
            title: "Can't Edit Grouped Data",
            body: "This query shows grouped/summarized data, not individual rows. To edit rows, select the table from the sidebar."
        )
    }

    // DISTINCT
    if normalizedQuery.contains("SELECT DISTINCT ") || normalizedQuery.contains("SELECT  DISTINCT ") {
        return EditabilityReason(
            title: "Can't Edit Distinct Results",
            body: "This query returns unique values only. To edit rows, select the table from the sidebar."
        )
    }

    // Window functions (OVER clause) - check before aggregates since aggregates can be used in window functions
    if normalizedQuery.contains(" OVER(") || normalizedQuery.contains(" OVER (") {
        return EditabilityReason(
            title: "Can't Edit Window Function Results",
            body: "This query includes window functions. To edit rows, select the table from the sidebar."
        )
    }

    // Aggregate functions (without OVER - those are caught above)
    let aggregates = ["COUNT(", "SUM(", "AVG(", "MIN(", "MAX(", "ARRAY_AGG(", "STRING_AGG(", "JSON_AGG(", "JSONB_AGG("]
    for agg in aggregates {
        if normalizedQuery.contains(agg) {
            return EditabilityReason(
                title: "Can't Edit Aggregated Data",
                body: "This query shows summarized data, not individual rows. To edit rows, select the table from the sidebar."
            )
        }
    }

    // Multiple tables in FROM (implicit cross join: FROM a, b)
    if hasMultipleTablesInFrom(normalizedQuery) {
        return EditabilityReason(
            title: "Can't Edit Multi-Table Results",
            body: "This query references multiple tables. To edit rows, select a single table from the sidebar."
        )
    }

    return nil
}

private func hasMultipleTablesInFrom(_ normalizedQuery: String) -> Bool {
    // Extract the FROM clause content
    guard let fromRange = normalizedQuery.range(of: "FROM ") else {
        return false
    }

    let afterFrom = String(normalizedQuery[fromRange.upperBound...])

    // Find where FROM clause ends (WHERE, ORDER, LIMIT, GROUP, HAVING, ;, or end)
    let terminators = [" WHERE ", " ORDER ", " LIMIT ", " GROUP ", " HAVING ", " OFFSET ", ";"]
    var fromClause = afterFrom
    for terminator in terminators {
        if let termRange = afterFrom.range(of: terminator) {
            let candidate = String(afterFrom[..<termRange.lowerBound])
            if candidate.count < fromClause.count {
                fromClause = candidate
            }
        }
    }

    // Check if there's a comma in the FROM clause (indicating multiple tables)
    // But we need to be careful about commas inside parentheses (subqueries)
    var depth = 0
    for char in fromClause {
        if char == "(" {
            depth += 1
        } else if char == ")" {
            depth -= 1
        } else if char == "," && depth == 0 {
            return true
        }
    }

    return false
}

private func extractTableFromSelect(_ query: String) -> (table: String, schema: String?)? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    // Pattern: FROM [schema.]table or FROM "schema"."table"
    // Handles: FROM users, FROM public.users, FROM "My Table", FROM "public"."My Table"
    let pattern = #"(?i)\bFROM\s+(?:(?:"([^"]+)"|(\w+))\.)?(?:"([^"]+)"|(\w+))"#

    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
        return nil
    }

    // Groups: 1=quoted schema, 2=unquoted schema, 3=quoted table, 4=unquoted table
    var schema: String?
    var table: String?

    // Extract schema (quoted or unquoted)
    if let range = Range(match.range(at: 1), in: trimmed), !trimmed[range].isEmpty {
        schema = String(trimmed[range])
    } else if let range = Range(match.range(at: 2), in: trimmed), !trimmed[range].isEmpty {
        schema = String(trimmed[range])
    }

    // Extract table (quoted or unquoted)
    if let range = Range(match.range(at: 3), in: trimmed), !trimmed[range].isEmpty {
        table = String(trimmed[range])
    } else if let range = Range(match.range(at: 4), in: trimmed), !trimmed[range].isEmpty {
        table = String(trimmed[range])
    }

    guard let tableName = table else {
        return nil
    }

    return (tableName, schema)
}
