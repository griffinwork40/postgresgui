//
//  RootViewModelTabHandling.swift
//  PostgresGUI
//
//  Tab switching logic extracted from RootViewModel.
//  Handles generation-counter-based race cancellation for async tab switches.
//

import Foundation
import SwiftData

extension RootViewModel {

    // MARK: - Tab Change Handling

    /// Handle tab switch: restore query state, connect if needed, load tables
    /// Now takes TabViewModel which is safe to access (not tied to SwiftData)
    func handleTabChange(_ tab: TabViewModel?, connections: [ConnectionProfile]) async {
        guard let tab = tab, !tab.isPendingDeletion else { return }

        // Increment generation to invalidate any in-flight tab switches
        incrementTabSwitchGeneration()
        let myGeneration = currentTabSwitchGeneration

        // Capture tab ID for validity checks after async operations
        let tabId = tab.id

        DebugLog.print("📑 [RootViewModel] Tab changed to: \(tabId) (generation: \(myGeneration))")

        // Set flag to prevent result-clearing during tab restore
        appState.query.isRestoringFromTab = true

        // Restore query text and saved query selection
        let previousQueryText = appState.query.queryText
        restoreQueryStateFromTab(tab)
        if previousQueryText != tab.queryText {
            DebugLog.print("📝 [RootViewModel] queryText changed from: \"\(previousQueryText.prefix(30))...\" to: \"\(tab.queryText.prefix(30))...\" (tab restore)")
        }

        // Restore cached results from tab (or clear if none)
        restoreCachedResultsFromTab(tab)

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            clearConnectionState()
            appState.query.isRestoringFromTab = false
            return
        }

        // Check if we're switching to the same connection AND database
        let sameConnection = appState.connection.currentConnection?.id == connectionId
        let sameDatabase = appState.connection.selectedDatabase?.name == tab.databaseName
        let isConnected = appState.connection.databaseService.isConnected

        if sameConnection && sameDatabase && isConnected && !appState.connection.tables.isEmpty {
            // Fast path: same connection and database, just restore table selection
            DebugLog.print("📑 [RootViewModel] Tab switch - same connection/database, restoring table selection only")
            restoreTableSelectionFromTab(tab)
            // Yield to let SwiftUI process onChange before clearing flag
            await Task.yield()
            appState.query.isRestoringFromTab = false
            return
        }

        // Set loading state and clear tables for full reload
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil
        appState.connection.tables = []

        // Connect if different connection or not connected
        if !sameConnection || !isConnected {
            let shouldContinue = await handleTabSwitchConnection(
                connection: connection,
                myGeneration: myGeneration,
                tabId: tabId
            )
            guard shouldContinue else { return }
        } else {
            DebugLog.print("🔌 [RootViewModel] Tab switch reusing existing connection to: \(connection.displayName)")
        }

        // Load databases and restore selection
        await handleTabSwitchDatabaseLoad(
            connection: connection,
            myGeneration: myGeneration,
            tabId: tabId
        )
    }

    // MARK: - Tab Switch Helpers

    private func handleTabSwitchConnection(
        connection: ConnectionProfile,
        myGeneration: UInt64,
        tabId: UUID
    ) async -> Bool {
        DebugLog.print("🔌 [RootViewModel] Tab switch requires connection to: \(connection.displayName)")
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: false)

        // Check if superseded after async operation
        guard isTabSwitchCurrent(myGeneration) else {
            DebugLog.print("📑 [RootViewModel] Tab switch superseded after connection (gen \(myGeneration) vs \(currentTabSwitchGeneration))")
            appState.query.isRestoringFromTab = false
            return false
        }

        // Check if tab was deleted during connection
        guard tabManager.isTabValid(tabId) else {
            DebugLog.print("📑 [RootViewModel] Tab was deleted during connection, aborting")
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return false
        }

        if case .failure(let error) = result {
            if case ConnectionError.connectionCancelled = error {
                DebugLog.print("📑 [RootViewModel] Tab switch connection was cancelled (superseded)")
                appState.connection.isLoadingTables = false
                appState.query.isRestoringFromTab = false
                return false
            }
            DebugLog.print("❌ [RootViewModel] Tab switch connection failed: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return false
        }
        DebugLog.print("✅ [RootViewModel] Tab switch connection successful")
        return true
    }

    private func handleTabSwitchDatabaseLoad(
        connection: ConnectionProfile,
        myGeneration: UInt64,
        tabId: UUID
    ) async {
        // Check if superseded before database fetch
        guard isTabSwitchCurrent(myGeneration) else {
            DebugLog.print("📑 [RootViewModel] Tab switch superseded before database fetch (gen \(myGeneration) vs \(currentTabSwitchGeneration))")
            appState.query.isRestoringFromTab = false
            return
        }

        // Load databases
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
        } catch {
            guard isTabSwitchCurrent(myGeneration) else {
                DebugLog.print("📑 [RootViewModel] Tab switch superseded during database fetch (gen \(myGeneration) vs \(currentTabSwitchGeneration))")
                appState.query.isRestoringFromTab = false
                return
            }
            if case ConnectionError.notConnected = error {
                DebugLog.print("📑 [RootViewModel] Tab switch got notConnected (likely superseded)")
                appState.connection.isLoadingTables = false
                appState.query.isRestoringFromTab = false
                return
            }
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        // Check if superseded after database fetch
        guard isTabSwitchCurrent(myGeneration) else {
            DebugLog.print("📑 [RootViewModel] Tab switch superseded after fetching databases (gen \(myGeneration) vs \(currentTabSwitchGeneration))")
            appState.query.isRestoringFromTab = false
            return
        }

        guard tabManager.isTabValid(tabId) else {
            DebugLog.print("📑 [RootViewModel] Tab was deleted during database fetch, aborting")
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        // Restore database selection
        guard let currentTab = tabManager.tab(by: tabId) else {
            DebugLog.print("📑 [RootViewModel] Tab no longer exists, aborting")
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        if let databaseName = currentTab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database
            await loadTables(for: database, connection: connection)

            guard isTabSwitchCurrent(myGeneration) else {
                DebugLog.print("📑 [RootViewModel] Tab switch superseded after loading tables (gen \(myGeneration) vs \(currentTabSwitchGeneration))")
                appState.query.isRestoringFromTab = false
                return
            }

            guard let finalTab = tabManager.tab(by: tabId) else {
                DebugLog.print("📑 [RootViewModel] Tab deleted after loading tables, aborting")
                appState.query.isRestoringFromTab = false
                return
            }

            restoreTableSelectionFromTab(finalTab)
            await Task.yield()
            appState.query.isRestoringFromTab = false
        } else {
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
        }
    }
}
