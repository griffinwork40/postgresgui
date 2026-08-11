//
//  RootViewModel.swift
//  PostgresGUI
//
//  Handles app initialization, tab switching, and connection restoration.
//  Uses TabViewModel (in-memory) for safe async operations - never accesses
//  SwiftData TabState directly.
//
//  Tab-switch handling is in RootViewModelTabHandling.swift.
//
//  Created by ghazi on 12/30/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class RootViewModel {
    // MARK: - Dependencies (internal for extension access)

    let appState: AppState
    let tabManager: TabManager
    let loadingState: LoadingState
    private let modelContext: ModelContext
    let keychainService: KeychainServiceProtocol
    private let tableRefreshService: TableRefreshServiceProtocol

    // MARK: - State

    var initializationError: String?

    /// Generation counter for tab switches - used to detect superseded operations
    /// More reliable than Task.isCancelled because state mutations happen synchronously
    private var tabSwitchGeneration: UInt64 = 0

    /// Current generation value for tab switch race detection.
    var currentTabSwitchGeneration: UInt64 { tabSwitchGeneration }

    /// Increment the tab-switch generation counter.
    func incrementTabSwitchGeneration() {
        tabSwitchGeneration &+= 1
    }

    /// Check if this tab switch is still the current one.
    func isTabSwitchCurrent(_ generation: UInt64) -> Bool {
        generation == tabSwitchGeneration
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        tabManager: TabManager,
        loadingState: LoadingState,
        modelContext: ModelContext,
        keychainService: KeychainServiceProtocol? = nil,
        tableRefreshService: TableRefreshServiceProtocol? = nil
    ) {
        self.appState = appState
        self.tabManager = tabManager
        self.loadingState = loadingState
        self.modelContext = modelContext
        let keychain = keychainService ?? KeychainServiceImpl()
        self.keychainService = keychain
        self.tableRefreshService = tableRefreshService ?? TableRefreshService(keychainService: keychain)
    }

    // MARK: - App Initialization

    /// Initialize the app: restore tabs, connect to last connection, load databases/tables
    func initializeApp(connections: [ConnectionProfile]) async {
        DebugLog.print("🚀 [RootViewModel] initializeApp started")

        // Initialize tab manager with model context
        loadingState.setPhase(.restoringTabs)
        tabManager.initialize(with: modelContext)

        // Wait for SwiftData to load connections
        try? await Task.sleep(nanoseconds: 0.1.nanoseconds)

        DebugLog.print("🚀 [RootViewModel] connections count: \(connections.count)")

        // If no connections exist, skip to ready state (welcome screen will show)
        guard !connections.isEmpty else {
            DebugLog.print("🚀 [RootViewModel] No connections, showing welcome")
            loadingState.setReady()
            return
        }

        // Get active tab's connection (use TabViewModel, not TabState)
        guard let activeTab = tabManager.activeTab,
              let connectionId = activeTab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            DebugLog.print("🚀 [RootViewModel] No connection to restore, finishing")
            loadingState.setReady()
            return
        }

        DebugLog.print("🚀 [RootViewModel] Restoring connection: \(connection.displayName)")

        // Restore query text and saved query selection from active tab
        restoreQueryStateFromTab(activeTab)

        // Connect to database
        loadingState.setPhase(.connectingToDatabase)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        if case .failure(let error) = result {
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Load databases
        loadingState.setPhase(.loadingDatabases)
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Restore database selection from active tab
        if let databaseName = activeTab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database

            // Load tables
            loadingState.setPhase(.loadingTables)
            await loadTables(for: database, connection: connection)

            // Restore table selection and cached results from tab
            restoreTableSelectionFromTab(activeTab)
            restoreCachedResultsFromTab(activeTab)
        }

        loadingState.setReady()
    }

    // MARK: - Tab State Management

    /// Save current state to active tab before switching or closing
    func saveCurrentStateToTab() {
        guard let activeTab = tabManager.activeTab, !activeTab.isPendingDeletion else { return }
        tabManager.updateActiveTab(
            connectionId: activeTab.connectionId,
            databaseName: activeTab.databaseName,
            queryText: appState.query.queryText,
            savedQueryId: appState.query.currentSavedQueryId
        )
    }

    /// Create a new tab inheriting from current
    func createNewTab() {
        saveCurrentStateToTab()
        tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
    }

    /// Close the current tab
    func closeCurrentTab() {
        guard let activeTab = tabManager.activeTab else { return }
        tabManager.closeTab(activeTab)
    }

    // MARK: - SQLite File Connection

    /// Open a SQLite database file and load its tables.
    func connectSQLiteFile(profile: DatabaseFileProfile) async {
        loadingState.setPhase(.connectingToDatabase)

        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connectFile(to: profile)
        guard case .success = result else {
            if case .failure(let error) = result {
                initializationError = error.localizedDescription
            }
            loadingState.setReady()
            return
        }

        loadingState.setPhase(.loadingTables)
        await loadTablesForSQLite()
        loadingState.setReady()
    }

    private func loadTablesForSQLite() async {
        appState.connection.isLoadingTables = true
        defer { appState.connection.isLoadingTables = false }
        do {
            let tables = try await appState.connection.databaseService.fetchTables(database: "main")
            appState.connection.tables = tables
            appState.connection.schemas = ["main"]
            appState.connection.selectedSchema = nil
            appState.connection.selectedDatabase = nil
            // SQLite has no SET search_path — skip setSchemaSearchPath
            DebugLog.print("✅ [RootViewModel] SQLite tables loaded: \(tables.count)")
        } catch {
            DebugLog.print("❌ [RootViewModel] Failed to load SQLite tables: \(error)")
            initializationError = error.localizedDescription
        }
    }

    // MARK: - Database Selection

    /// Select a database and load its tables
    func selectDatabase(_ database: DatabaseInfo) async {
        guard let connection = appState.connection.currentConnection else { return }

        appState.connection.selectedDatabase = database
        appState.connection.tables = []
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil

        await loadTables(for: database, connection: connection)
    }

    // MARK: - Shared Helpers (used by extension)

    func restoreQueryStateFromTab(_ tab: TabViewModel) {
        appState.query.queryText = tab.queryText
        appState.query.currentSavedQueryId = tab.savedQueryId
        restoreSavedQueryMetadata(for: tab.savedQueryId)
    }

    func restoreCachedResultsFromTab(_ tab: TabViewModel) {
        DebugLog.print("📊 [RootViewModel] Restoring cached results from tab \(tab.id)")

        guard !tab.isPendingDeletion else {
            DebugLog.print("📊 [RootViewModel] Tab is pending deletion, skipping cache restore")
            return
        }

        if let cachedResults = tab.cachedResults {
            appState.query.queryResults = cachedResults
            appState.query.queryColumnNames = tab.cachedColumnNames
            appState.query.showQueryResults = true
            if let schema = tab.selectedTableSchema, let name = tab.selectedTableName {
                appState.query.cachedResultsTableId = "\(schema).\(name)"
            } else {
                appState.query.cachedResultsTableId = nil
            }
            DebugLog.print("📊 [RootViewModel] Restored \(cachedResults.count) cached query results, showQueryResults=true")
        } else {
            DebugLog.print("📊 [RootViewModel] No cached results in tab, clearing")
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.cachedResultsTableId = nil
        }
    }

    func restoreTableSelectionFromTab(_ tab: TabViewModel) {
        guard !tab.isPendingDeletion else { return }

        appState.connection.selectedSchema = tab.selectedSchemaFilter
        appState.setSchemaSearchPathDebounced(tab.selectedSchemaFilter)

        if let tableSchema = tab.selectedTableSchema,
           let tableName = tab.selectedTableName,
           let table = appState.connection.tables.first(where: {
               $0.schema == tableSchema && $0.name == tableName
           }) {
            appState.connection.selectedTable = table
        } else {
            appState.connection.selectedTable = nil
        }
    }

    func clearConnectionState() {
        appState.connection.currentConnection = nil
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
        appState.connection.databases = []
        appState.connection.databasesVersion += 1
        appState.connection.tables = []
        appState.connection.isLoadingTables = false
    }

    // MARK: - Private Helpers

    private func restoreSavedQueryMetadata(for savedQueryId: UUID?) {
        guard let savedQueryId = savedQueryId else {
            appState.query.currentQueryName = nil
            appState.query.lastSavedAt = nil
            return
        }

        let descriptor = FetchDescriptor<SavedQuery>(
            predicate: #Predicate { $0.id == savedQueryId }
        )
        if let savedQuery = try? modelContext.fetch(descriptor).first {
            appState.query.currentQueryName = savedQuery.name
            appState.query.lastSavedAt = savedQuery.updatedAt
        }
    }

    func loadTables(for database: DatabaseInfo, connection: ConnectionProfile) async {
        await tableRefreshService.loadTables(
            for: database,
            connection: connection,
            appState: appState
        )
    }
}
