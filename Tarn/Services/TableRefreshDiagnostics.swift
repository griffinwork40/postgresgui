//
//  TableRefreshDiagnostics.swift
//  Tarn
//
//  Diagnostic helpers and state-mutation utilities extracted from TableRefreshService
//  to keep that file under the 350-line ceiling.
//

import Foundation

// MARK: - Diagnostics & Helper Methods

@MainActor
extension TableRefreshService {

    // MARK: State Summaries

    func refreshStateSummary(appState: AppState) -> String {
        let connectionName = appState.connection.currentConnection?.name ?? "nil"
        let selectedDatabase = appState.connection.selectedDatabase?.name ?? "nil"
        let selectedTable = appState.connection.selectedTable?.id ?? "nil"
        let selectedSchema = appState.connection.selectedSchema ?? "nil"
        let connectedDatabase = appState.connection.databaseService.connectedDatabase ?? "nil"
        return (
            "(connection: \(connectionName), " +
            "selectedDB: \(selectedDatabase), " +
            "selectedTable: \(selectedTable), " +
            "selectedSchema: \(selectedSchema), " +
            "connectedDB: \(connectedDatabase), " +
            "isConnected: \(appState.connection.databaseService.isConnected), " +
            "isLoadingTables: \(appState.connection.isLoadingTables), " +
            "databases: \(appState.connection.databases.count), " +
            "tables: \(appState.connection.tables.count), " +
            "schemas: \(appState.connection.schemas.count))"
        )
    }

    func loadTablesStateSummary(for database: DatabaseInfo, appState: AppState) -> String {
        let selectedDatabase = appState.connection.selectedDatabase?.name ?? "nil"
        let connectedDatabase = appState.connection.databaseService.connectedDatabase ?? "nil"
        return (
            "(targetDB: \(database.name), " +
            "selectedDB: \(selectedDatabase), " +
            "connectedDB: \(connectedDatabase), " +
            "isConnected: \(appState.connection.databaseService.isConnected), " +
            "isLoadingTables: \(appState.connection.isLoadingTables), " +
            "tables: \(appState.connection.tables.count), " +
            "schemas: \(appState.connection.schemas.count))"
        )
    }

    // MARK: State Mutation Helpers

    func clearSelectionForMissingDatabase(appState: AppState) async {
        DebugLog.print(
            "🧹 [TableRefreshService] Clearing database-dependent selection state " +
            refreshStateSummary(appState: appState)
        )
        let hadSchemaSelection = appState.connection.selectedSchema != nil
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
        appState.connection.tables = []
        appState.connection.schemas = []
        appState.connection.selectedSchema = nil
        appState.connection.tableMetadataCache = [:]
        if hadSchemaSelection {
            await appState.setSchemaSearchPath(nil)
        }
    }

    func pruneStaleTableMetadataCache(appState: AppState, refreshedTables: [TableInfo]) {
        let previousCount = appState.connection.tableMetadataCache.count
        let validTableIds = Set(refreshedTables.map(\.id))
        appState.connection.tableMetadataCache = appState.connection.tableMetadataCache.filter {
            validTableIds.contains($0.key)
        }
        let prunedCount = previousCount - appState.connection.tableMetadataCache.count
        if prunedCount > 0 {
            DebugLog.print("🧹 [TableRefreshService] Pruned \(prunedCount) stale table metadata cache entries")
        }
    }

    /// Updates selectedTable reference if it still exists in the refreshed list.
    func updateSelectedTable(appState: AppState) {
        guard let selectedTable = appState.connection.selectedTable,
              let refreshedTable = appState.connection.tables.first(where: { $0.id == selectedTable.id }) else {
            if appState.connection.selectedTable != nil {
                DebugLog.print(
                    "🧹 [TableRefreshService] Selected table no longer exists after refresh; clearing selection " +
                    refreshStateSummary(appState: appState)
                )
                appState.connection.selectedTable = nil
            }
            return
        }

        // Only update if metadata changed
        if refreshedTable != selectedTable {
            DebugLog.print(
                "♻️ [TableRefreshService] Rebinding selected table to refreshed metadata " +
                "(table: \(selectedTable.id))"
            )
            appState.connection.selectedTable = refreshedTable
        } else {
            DebugLog.print(
                "📌 [TableRefreshService] Preserving selected table after refresh " +
                "(table: \(selectedTable.id))"
            )
        }
    }
}
