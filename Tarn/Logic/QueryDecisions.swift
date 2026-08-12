//
//  QueryDecisions.swift
//  Tarn
//
//  Pure functions for query-related decisions.
//  Extracted from view models to enable unit testing.
//

import Foundation

// MARK: - Cache Decisions

/// Determines whether to use cached query results or execute a new query
/// - Parameters:
///   - hasResults: Whether there are existing results in state
///   - cachedTableId: The table ID associated with cached results
///   - selectedTableId: The currently selected table ID
/// - Returns: True if cached results should be used
func shouldUseCachedResults(
    hasResults: Bool,
    cachedTableId: String?,
    selectedTableId: String?
) -> Bool {
    guard hasResults else { return false }
    guard let cached = cachedTableId, let selected = selectedTableId else { return false }
    return cached == selected
}

/// Determines whether to clear results when table selection changes
/// - Parameters:
///   - oldTableId: Previously selected table ID
///   - newTableId: Newly selected table ID
///   - hasCachedResultsForNewTable: Whether we have cached results for the new table
/// - Returns: True if results should be cleared
func shouldClearResultsOnTableChange(
    oldTableId: String?,
    newTableId: String?,
    hasCachedResultsForNewTable: Bool
) -> Bool {
    oldTableId != newTableId && !hasCachedResultsForNewTable
}

// MARK: - Table Refresh Decisions

/// Determines whether the selected table should be refreshed after a mutation
/// - Parameters:
///   - mutatedTableName: The table name affected by the mutation (from SQL parsing)
///   - selectedTableName: The currently selected table name
/// - Returns: True if the selected table should be refreshed
func shouldRefreshTableAfterMutation(
    mutatedTableName: String?,
    selectedTableName: String?
) -> Bool {
    guard let mutated = mutatedTableName,
          let selected = selectedTableName else {
        return false
    }
    return tableNamesMatch(mutated, selected)
}

/// Case-insensitive comparison of table names
/// Handles schema-qualified names by comparing just the table part
func tableNamesMatch(_ name1: String, _ name2: String) -> Bool {
    let clean1 = extractTableNamePart(name1)
    let clean2 = extractTableNamePart(name2)
    return clean1.lowercased() == clean2.lowercased()
}

/// Extracts the table name part from a potentially schema-qualified name
private func extractTableNamePart(_ name: String) -> String {
    if name.contains(".") {
        return name.components(separatedBy: ".").last ?? name
    }
    return name
}

// MARK: - Rollback Safety

/// Determines if it's safe to rollback optimistic updates after a failure
/// - Parameters:
///   - versionAtOperationStart: The results version when the operation began
///   - currentVersion: The current results version
/// - Returns: True if safe to rollback (results haven't been replaced)
func isSafeToRollback(versionAtOperationStart: Int, currentVersion: Int) -> Bool {
    versionAtOperationStart == currentVersion
}

// MARK: - Schema Detection

/// Check if SQL contains schema-modifying statements that affect the tables list
func isSchemaModifyingQuery(_ sql: String) -> Bool {
    let upperSQL = sql.uppercased()
    let patterns = [
        "CREATE\\s+TABLE",
        "DROP\\s+TABLE",
        "ALTER\\s+TABLE",
        "CREATE\\s+TEMP(ORARY)?\\s+TABLE"
    ]
    return patterns.contains { pattern in
        upperSQL.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Check if SQL is a DROP TABLE statement
func isDropTableQuery(_ sql: String) -> Bool {
    sql.uppercased().range(of: "DROP\\s+TABLE", options: .regularExpression) != nil
}

// MARK: - Pagination

/// Determines if there are more pages of results
/// - Parameters:
///   - fetchedRowCount: Number of rows returned from query
///   - pageSize: The configured page size (rows per page)
/// - Returns: True if there are more pages (fetched more than pageSize)
func hasMorePages(fetchedRowCount: Int, pageSize: Int) -> Bool {
    fetchedRowCount > pageSize
}

/// Determines if user can navigate to the previous page
/// - Parameter currentPage: Current page number (0-indexed)
/// - Returns: True if not on the first page
func canGoToPreviousPage(currentPage: Int) -> Bool {
    currentPage > 0
}

/// Calculates the offset for a paginated query
/// - Parameters:
///   - page: Page number (0-indexed)
///   - pageSize: Rows per page
/// - Returns: The OFFSET value for SQL query
func calculateOffset(page: Int, pageSize: Int) -> Int {
    page * pageSize
}
