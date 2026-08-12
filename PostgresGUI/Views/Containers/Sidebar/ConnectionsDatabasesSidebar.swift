//
//  ConnectionsDatabasesSidebar.swift
//  PostgresGUI
//
//  Sidebar for connection and database selection. Delegates business logic to ConnectionSidebarViewModel.
//

import SwiftData
import SwiftUI

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(LoadingState.self) private var loadingState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.keychainService) private var keychainService

    @Query private var connections: [ConnectionProfile]

    @State private var viewModel: ConnectionSidebarViewModel?

    // Connection dropdown state
    @State private var showConnectionDropdown = false

    // Database dropdown state
    @State private var showDatabaseDropdown = false

    @State private var isRefreshButtonHovered = false

    var body: some View {
        contentWithChangeHandlers
            .onAppear {
                _ = ensureViewModel()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        DebugLog.print(
                            "🔄 [ConnectionsDatabasesSidebar] Refresh toolbar button clicked " +
                            refreshButtonLogContext
                        )
                        appState.connection.sidebarRefreshFeedbackRequestId += 1
                        let requestId = appState.connection.sidebarRefreshFeedbackRequestId
                        appState.connection.isRefreshingSidebarMetadata = true
                        Task { @MainActor in
                            let feedbackStartedAt = Date()
                            await ensureViewModel().refreshOnDemandFromToolbar()
                            let remainingFeedbackDuration = max(0, 0.45 - Date().timeIntervalSince(feedbackStartedAt))
                            if remainingFeedbackDuration > 0 {
                                try? await Task.sleep(nanoseconds: remainingFeedbackDuration.nanoseconds)
                            }
                            if appState.connection.sidebarRefreshFeedbackRequestId == requestId {
                                appState.connection.isRefreshingSidebarMetadata = false
                            }
                        }
                    } label: {
                        ZStack {
                            if appState.connection.isRefreshingSidebarMetadata {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.86)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                        .frame(width: 34, height: 26)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(RefreshToolbarButtonStyle(
                        isActive: appState.connection.isRefreshingSidebarMetadata,
                        isHovered: isRefreshButtonHovered
                    ))
                    .onHover { isHovering in
                        isRefreshButtonHovered = isHovering
                    }
                    .help("Refreshes database list and table list.")
                }
            }
            .modifier(DatabaseAlertsModifier(
                showConnectionError: Binding(
                    get: { viewModel?.showConnectionError ?? false },
                    set: { viewModel?.showConnectionError = $0 }
                ),
                connectionError: Binding(
                    get: { viewModel?.connectionError },
                    set: { viewModel?.connectionError = $0 }
                ),
                databaseToDelete: Binding(
                    get: { viewModel?.databaseToDelete },
                    set: { viewModel?.databaseToDelete = $0 }
                ),
                deleteError: Binding(
                    get: { viewModel?.deleteError },
                    set: { viewModel?.deleteError = $0 }
                ),
                deleteDatabase: { database in
                    await viewModel?.deleteDatabase(database)
                }
            ))
            .modifier(ConnectionAlertsModifier(
                connectionToDelete: Binding(
                    get: { viewModel?.connectionToDelete },
                    set: { viewModel?.connectionToDelete = $0 }
                ),
                deleteConnection: { connection in
                    await viewModel?.deleteConnection(connection)
                }
            ))
            .modifier(TableLoadingTimeoutAlertModifier(
                appState: appState,
                retryAction: {
                    Task {
                        await viewModel?.retryTableLoading()
                    }
                }
            ))
            .alert("Schema Error", isPresented: Binding(
                get: { appState.connection.schemaError != nil },
                set: { if !$0 { appState.connection.schemaError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    appState.connection.schemaError = nil
                }
            } message: {
                if let error = appState.connection.schemaError {
                    Text(error)
                }
            }
    }

    private var contentWithChangeHandlers: some View {
        mainContent
            .onChange(of: appState.connection.currentConnection) { oldValue, newValue in
                viewModel?.handleConnectionChange(oldValue: oldValue, newValue: newValue)
            }
            .task {
                await viewModel?.waitForInitialLoad()
                await viewModel?.restoreLastConnection(connections: connections)
            }
            .onChange(of: appState.connection.currentConnection) { _, newConnection in
                viewModel?.updateTabForConnectionChange(newConnection)
            }
            .onChange(of: appState.connection.selectedDatabase) { _, newDatabase in
                viewModel?.updateTabForDatabaseChange(newDatabase)
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            makeConnectionDatabasePicker()
            if appState.connection.selectedDatabase != nil && appState.connection.schemas.count > 1 {
                SchemaPicker(
                    schemas: appState.connection.schemas,
                    selectedSchema: appState.connection.selectedSchema,
                    onSelect: handleSelectSchema
                )
            }
            makeTablesList()
        }
    }

    private func handleSelectSchema(_ schema: String?) {
        appState.connection.selectedSchema = schema
        // Clear selected table if it's not in the new schema
        if let selected = appState.connection.selectedTable,
           let schema = schema,
           selected.schema != schema {
            appState.connection.selectedTable = nil
        }
        // Set search_path for query context (debounced to handle rapid changes)
        appState.setSchemaSearchPathDebounced(schema)
        // Save to tab state
        tabManager.updateActiveTabSchemaFilter(schema)
    }

    @ViewBuilder
    private func makeTablesList() -> some View {
        @Bindable var appState = appState

        TablesListIsolated(
            tables: appState.connection.filteredTables,
            groupedTables: appState.connection.groupedTables,
            selectedSchema: appState.connection.selectedSchema,
            selectedTable: Binding(
                get: { appState.connection.selectedTable },
                set: { appState.connection.selectedTable = $0 }
            ),
            expandedSchemas: Binding(
                get: { appState.connection.expandedSchemas },
                set: { appState.connection.expandedSchemas = $0 }
            ),
            isLoadingTables: appState.connection.isLoadingTables,
            isShowingRefreshFeedback: appState.connection.isRefreshingSidebarMetadata,
            isExecutingQuery: appState.query.isExecutingQuery,
            selectedDatabase: appState.connection.selectedDatabase,
            refreshQueryAction: { table in
                appState.requestTableQuery(for: table)
            }
        )
    }

    // MARK: - Connection/Database Picker

    @ViewBuilder
    private func makeConnectionDatabasePicker() -> some View {
        ConnectionDatabasePicker(
            showConnectionDropdown: $showConnectionDropdown,
            connections: connections,
            onSelectConnection: handleSelectConnection,
            onEditConnection: handleEditConnection,
            onDeleteConnection: handleDeleteConnection,
            onCreateConnection: handleCreateConnection,
            showDatabaseDropdown: $showDatabaseDropdown,
            onSelectDatabase: handleSelectDatabase,
            onDeleteDatabase: handleDeleteDatabase,
            onCreateDatabase: handleCreateDatabase
        )
    }

    private func handleSelectConnection(_ connection: ConnectionProfile) {
        Task {
            await viewModel?.selectConnection(connection)
        }
    }

    private func handleEditConnection(_ connection: ConnectionProfile) {
        // TODO: SQLite-only build — Postgres connection editing is not available.
        // ConnectionFormView was removed. Wire to a future SQLite profile editor if needed.
    }

    private func handleDeleteConnection(_ connection: ConnectionProfile) {
        viewModel?.connectionToDelete = connection
    }

    private func handleCreateConnection() {
        // TODO: SQLite-only build — Postgres connection creation is not available.
        // ConnectionFormView was removed. Use FileOpenView (showFileOpen) for SQLite files.
    }

    private func handleSelectDatabase(_ database: DatabaseInfo) {
        viewModel?.selectDatabase(database)
    }

    private func handleDeleteDatabase(_ database: DatabaseInfo) {
        viewModel?.databaseToDelete = database
    }

    private func handleCreateDatabase() {
        // TODO(sqlite): showCreateDatabase() / CreateDatabaseView is Postgres-only dead code for SQLite.
        // Leave in place — removing it changes the picker interface.
        appState.navigation.showCreateDatabase()
    }

    @MainActor
    private func ensureViewModel() -> ConnectionSidebarViewModel {
        if let viewModel {
            return viewModel
        }

        DebugLog.print(
            "🧩 [ConnectionsDatabasesSidebar] Creating ConnectionSidebarViewModel " +
            refreshButtonLogContext
        )
        let newViewModel = ConnectionSidebarViewModel(
            appState: appState,
            tabManager: tabManager,
            loadingState: loadingState,
            modelContext: modelContext,
            keychainService: keychainService
        )
        viewModel = newViewModel
        return newViewModel
    }

    private var refreshButtonLogContext: String {
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
            "isRefreshingSidebarMetadata: \(appState.connection.isRefreshingSidebarMetadata), " +
            "databases: \(appState.connection.databases.count), " +
            "tables: \(appState.connection.tables.count))"
        )
    }
}

