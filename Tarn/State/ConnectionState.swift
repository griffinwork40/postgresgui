//
//  ConnectionState.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import Foundation

// MARK: - Active Connection

/// Discriminated union representing the currently active connection (Postgres or SQLite file).
enum ActiveConnection {
    case postgres(ConnectionProfile)
    case sqlite(DatabaseFileProfile)

    var postgresProfile: ConnectionProfile? {
        if case .postgres(let p) = self { return p }
        return nil
    }

    var sqliteProfile: DatabaseFileProfile? {
        if case .sqlite(let p) = self { return p }
        return nil
    }
}

// MARK: - ConnectionState

/// Manages database connection state and data caches
@Observable
@MainActor
class ConnectionState {
    // Active connection (Postgres or SQLite file)
    var activeConnection: ActiveConnection?

    /// Backward-compatible shim: returns the Postgres profile when connected via Postgres.
    /// Setting this property wraps the profile in `.postgres(_)`.
    var currentConnection: ConnectionProfile? {
        get { activeConnection?.postgresProfile }
        set { activeConnection = newValue.map { .postgres($0) } }
    }

    // Computed property - delegates to DatabaseServiceProtocol
    var isConnected: Bool {
        databaseService.isConnected
    }

    // Database service dependency - injected for testability
    var databaseService: DatabaseServiceProtocol

    init(databaseService: DatabaseServiceProtocol) {
        self.databaseService = databaseService
    }

    convenience init() {
        self.init(databaseService: SQLiteDatabaseService())
    }

    // Current selections
    var selectedDatabase: DatabaseInfo?
    var selectedTable: TableInfo?
    var selectedSchema: String? = nil {  // nil means "All Schemas"
        didSet {
            if oldValue != selectedSchema {
                invalidateTableCache()
            }
        }
    }
    var schemaError: String? = nil  // Error message when SET search_path fails

    // Schema group expansion state (for sidebar)
    var expandedSchemas: Set<String> = []

    // Table expansion state (for showing columns in sidebar)
    // Key: table ID (schema.name), Value: whether columns are shown
    var expandedTables: Set<String> = []

    // Data caches (populated by the database service)
    var databases: [DatabaseInfo] = []
    var databasesVersion: Int = 0
    var schemas: [String] = []
    var tables: [TableInfo] = [] {
        didSet {
            invalidateTableCache()
        }
    }

    /// Cached filtered tables - updated via invalidateTableCache()
    private(set) var filteredTables: [TableInfo] = []

    /// Cached grouped tables - updated via invalidateTableCache()
    private(set) var groupedTables: [SchemaGroup] = []

    /// Recomputes filteredTables and groupedTables from source data.
    /// Called automatically when `tables` or `selectedSchema` changes.
    private func invalidateTableCache() {
        if let schema = selectedSchema {
            filteredTables = tables.filter { $0.schema == schema }
        } else {
            filteredTables = tables
        }
        groupedTables = groupTablesBySchema(filteredTables)
    }
    var isLoadingTables: Bool = false
    var isRefreshingSidebarMetadata: Bool = false
    var sidebarRefreshFeedbackRequestId: Int = 0
    var tableLoadingError: Error? = nil
    var showTableLoadingTimeoutAlert: Bool = false

    /// Check if the current table loading error is a timeout
    var isTableLoadingTimeout: Bool {
        guard let error = tableLoadingError else { return false }
        return DatabaseError.isTimeout(error)
    }

    // Separate metadata cache to avoid triggering List re-renders
    // Key: table ID (schema.name), Value: (primaryKeyColumns, columnInfo)
    var tableMetadataCache: [String: (primaryKeys: [String]?, columns: [ColumnInfo]?)] = [:]

    // MARK: - Metadata Cache Helpers

    /// Get primary keys for a table, checking cache first, then selectedTable
    func getPrimaryKeys(for table: TableInfo) -> [String]? {
        return tableMetadataCache[table.id]?.primaryKeys ?? table.primaryKeyColumns
    }

    /// Get column info for a table, checking cache first, then selectedTable
    func getColumnInfo(for table: TableInfo) -> [ColumnInfo]? {
        return tableMetadataCache[table.id]?.columns ?? table.columnInfo
    }

    /// Check if table has primary keys (either cached or in table metadata)
    func hasPrimaryKeys(for table: TableInfo) -> Bool {
        guard let pkColumns = getPrimaryKeys(for: table) else { return false }
        return !pkColumns.isEmpty
    }
    
    /// Check if a table is still the currently selected table
    /// Useful for race condition checks during async operations
    func isTableStillSelected(_ tableId: String) -> Bool {
        selectedTable?.id == tableId
    }

    /// Check if the full query context is still valid (table, database, and connection)
    /// Prevents stale results when same table name exists in different databases/connections
    func isQueryContextValid(tableId: String, databaseId: String?, connectionId: UUID?) -> Bool {
        selectedTable?.id == tableId &&
        selectedDatabase?.id == databaseId &&
        currentConnection?.id == connectionId
    }

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up connection...")

        // Full shutdown including EventLoopGroup
        await databaseService.shutdown()

        // Reset state — set activeConnection directly; currentConnection is a computed shim over it
        activeConnection = nil
        selectedDatabase = nil
        selectedTable = nil
        selectedSchema = nil
        expandedSchemas = []
        expandedTables = []
        databases = []
        databasesVersion += 1
        schemas = []
        tables = []
        isLoadingTables = false
        isRefreshingSidebarMetadata = false
        sidebarRefreshFeedbackRequestId = 0
        tableMetadataCache = [:]

        DebugLog.print("✅ Cleanup completed")
    }
}
