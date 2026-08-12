//
//  ConnectionSidebarRefreshCoordinator.swift
//  Tarn
//
//  Manual refresh lifecycle for ConnectionSidebarViewModel.
//  Extracted to keep the main file under the 350-line ceiling.
//

import Foundation

// MARK: - Manual Refresh Lifecycle

extension ConnectionSidebarViewModel {

    /// Triggered by sidebar toolbar refresh button.
    /// Uses latest-wins semantics for rapid repeated clicks.
    func refreshOnDemandFromToolbar() async {
        manualRefreshRequestId += 1
        let requestId = manualRefreshRequestId
        let hadExistingTask = manualRefreshTask != nil

        if hadExistingTask {
            DebugLog.print(
                "🔄 [ConnectionSidebarViewModel] Cancelling previous manual refresh before starting request \(requestId) " +
                refreshStateSummary()
            )
        }
        manualRefreshTask?.cancel()

        DebugLog.print(
            "🔄 [ConnectionSidebarViewModel] Manual refresh requested " +
            "(id: \(requestId), hadExistingTask: \(hadExistingTask)) " +
            refreshStateSummary()
        )
        manualRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            DebugLog.print(
                "🔄 [ConnectionSidebarViewModel] Manual refresh started " +
                "(id: \(requestId)) " +
                self.refreshStateSummary()
            )
            await self.tableRefreshService.refresh(appState: self.appState)
            let duration = Date().timeIntervalSince(startedAt)
            if Task.isCancelled {
                DebugLog.print(
                    "⚠️ [ConnectionSidebarViewModel] Manual refresh task cancelled " +
                    "(id: \(requestId), duration: \(String(format: "%.3f", duration))s) " +
                    self.refreshStateSummary()
                )
            } else {
                DebugLog.print(
                    "✅ [ConnectionSidebarViewModel] Manual refresh task returned from service " +
                    "(id: \(requestId), duration: \(String(format: "%.3f", duration))s) " +
                    self.refreshStateSummary()
                )
            }
        }
        await manualRefreshTask?.value

        if manualRefreshRequestId == requestId {
            manualRefreshTask = nil
            DebugLog.print(
                "🏁 [ConnectionSidebarViewModel] Manual refresh lifecycle finished " +
                "(id: \(requestId)) " +
                refreshStateSummary()
            )
        } else {
            DebugLog.print(
                "↪️ [ConnectionSidebarViewModel] Manual refresh request \(requestId) completed " +
                "after a newer request became active " +
                refreshStateSummary()
            )
        }
    }

    func refreshStateSummary() -> String {
        let connectionName = appState.connection.currentConnection?.name ?? "nil"
        let selectedDatabase = appState.connection.selectedDatabase?.name ?? "nil"
        let selectedTable = appState.connection.selectedTable?.id ?? "nil"
        let connectedDatabase = appState.connection.databaseService.connectedDatabase ?? "nil"
        return (
            "(connection: \(connectionName), " +
            "selectedDB: \(selectedDatabase), " +
            "selectedTable: \(selectedTable), " +
            "connectedDB: \(connectedDatabase), " +
            "isConnected: \(appState.connection.databaseService.isConnected), " +
            "isLoadingTables: \(appState.connection.isLoadingTables), " +
            "databases: \(appState.connection.databases.count), " +
            "tables: \(appState.connection.tables.count), " +
            "schemas: \(appState.connection.schemas.count))"
        )
    }
}
