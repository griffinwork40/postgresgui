//
//  QueryEditorViewModel.swift
//  Tarn
//
//  Handles query execution, auto-save, and schema detection.
//  Extracted from QueryEditorView to separate business logic from presentation.
//

import Foundation
import SwiftData

@Observable
@MainActor
class QueryEditorViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let modelContext: ModelContext
    private let queryService: QueryServiceProtocol
    private let persistence: QueryPersistenceService

    // MARK: - State

    var showNoDatabaseAlert = false
    var showSaveErrorAlert = false
    var saveErrorMessage = ""

    private var saveTask: Task<Void, Never>?
    private var queryExecutionRequestId: Int = 0

    // MARK: - Initialization

    init(
        appState: AppState,
        tabManager: TabManager,
        modelContext: ModelContext,
        queryService: QueryServiceProtocol? = nil
    ) {
        self.appState = appState
        self.tabManager = tabManager
        self.modelContext = modelContext
        self.persistence = QueryPersistenceService(
            appState: appState,
            tabManager: tabManager,
            modelContext: modelContext
        )
        self.queryService = queryService ?? QueryService(
            databaseService: appState.connection.databaseService,
            queryState: appState.query
        )
    }

    // MARK: - Query Text Change Handling

    /// Handle query text changes: debounced auto-save and tab update
    func handleQueryTextChange(_ newText: String) {
        // Capture restoration flag now (before debounce)
        let isRestoring = appState.query.isRestoringFromTab

        // Cancel previous save task
        saveTask?.cancel()

        // Debounced auto-save (500ms) - skip if restoring from tab
        if !isRestoring {
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else {
                    DebugLog.print("💾 [QueryEditorViewModel] Auto-save cancelled (new keystroke)")
                    return
                }
                tabManager.syncActiveTabToStorage(includeCachedResults: false)
                DebugLog.print("💾 [QueryEditorViewModel] Auto-save triggered after debounce")
                let result = await persistence.saveWithRetry()
                if !result.success, let msg = result.errorMessage {
                    saveErrorMessage = msg
                    showSaveErrorAlert = true
                }
            }
        }

        // Update tab state immediately in memory; persistence is debounced above.
        tabManager.updateActiveTab(
            connectionId: nil,
            databaseName: nil,
            queryText: newText,
            persistToStorage: false
        )
    }

    // MARK: - Query Execution

    /// Execute the current query
    func executeQuery() async {
        DebugLog.print("🎬 [QueryEditorViewModel] Execute button clicked")

        // Check if database is selected
        guard let database = appState.connection.selectedDatabase else {
            showNoDatabaseAlert = true
            DebugLog.print("⚠️ [QueryEditorViewModel] No database selected")
            return
        }

        // Capture the tab that initiated this query
        guard let executingTab = tabManager.activeTab else {
            DebugLog.print("⚠️ [QueryEditorViewModel] No active tab")
            return
        }

        let executingTabId = executingTab.id
        let queryText = appState.query.queryText
        let queryType = QueryTypeDetector.detect(queryText)
        let tableName = QueryTypeDetector.extractTableName(queryText)
        queryExecutionRequestId += 1
        let requestId = queryExecutionRequestId

        // Capture the saved query ID that initiated this execution
        let executingSavedQueryId = appState.query.currentSavedQueryId

        // Start execution tracking on the tab
        executingTab.startQueryExecution()

        // Set loading state on global QueryState (for active tab display)
        appState.query.startQueryExecution()
        appState.query.executingSavedQueryId = executingSavedQueryId

        // Execute query using QueryService
        DebugLog.print("🧭 [QueryEditorViewModel] Run Query tableName: \(tableName ?? "nil")")
        let preferredColumnOrder = await appState.preferredColumnOrder(forTableName: tableName)
        DebugLog.print("🧭 [QueryEditorViewModel] Preferred column order count: \(preferredColumnOrder?.count ?? 0)")
        let result = await queryService.executeQuery(
            queryText,
            preferredColumnOrder: preferredColumnOrder
        )

        guard requestId == queryExecutionRequestId else {
            DebugLog.print("⚠️ [QueryEditorViewModel] Query result superseded, ignoring stale completion")
            return
        }

        if let error = result.error, isCancellationLike(error) {
            DebugLog.print("⚠️ [QueryEditorViewModel] Query cancelled/superseded before completion")
            executingTab.finishQueryExecution()
            return
        }

        // Finish execution tracking on the tab
        executingTab.finishQueryExecution()

        // Log to QueryHistory
        let historyEntry = QueryHistory(
            queryText: queryText,
            executionTime: result.executionTime,
            isSuccess: result.isSuccess,
            databaseName: database.name,
            connectionId: appState.connection.currentConnection?.id
        )
        modelContext.insert(historyEntry)
        try? modelContext.save()

        // Check if this tab is still the active tab AND the same saved query is still selected
        let isStillActiveTab = tabManager.activeTab?.id == executingTabId
        let isSameSavedQuery = appState.query.currentSavedQueryId == executingSavedQueryId

        // Clear the executing saved query ID
        appState.query.executingSavedQueryId = nil

        if result.isSuccess {
            if queryType.isMutation && result.rows.isEmpty {
                // Mutation query with no returned rows: keep previous results, show toast
                // Only update UI if same query is still active
                if isStillActiveTab && isSameSavedQuery {
                    appState.query.isExecutingQuery = false
                    appState.query.queryExecutionTime = result.executionTime
                    appState.query.stopElapsedTimeTracking()

                    appState.query.showMutationToast(
                        type: queryType,
                        tableName: tableName
                    )
                    appState.query.setTemporaryStatus("Executed in \(QueryState.formatExecutionTime(result.executionTime))")
                }
                DebugLog.print("✅ [QueryEditorViewModel] Mutation query executed, showing toast")

                // Refresh table results if mutation was on the currently selected table
                if let selectedTable = appState.connection.selectedTable,
                   shouldRefreshTableAfterMutation(mutatedTableName: tableName, selectedTableName: selectedTable.name) {
                    DebugLog.print("🔄 [QueryEditorViewModel] Refreshing selected table after mutation")
                    await appState.executeTableQuery(for: selectedTable)
                }
            } else {
                // Query returned rows (SELECT, or mutation with RETURNING): show results
                // Only update global state if same query is still active
                if isStillActiveTab && isSameSavedQuery {
                    appState.query.finishQueryExecution(with: result)
                    appState.query.setTemporaryStatus("Executed in \(QueryState.formatExecutionTime(result.executionTime))")
                    appState.query.isResultsReadOnlyDueToContextMismatch = false
                }
                DebugLog.print("✅ [QueryEditorViewModel] Query executed, showing \(result.rows.count) results")

                // Cache results to the executing tab (even if user switched away)
                DebugLog.print("💾 [QueryEditorViewModel] Caching \(result.rows.count) results to tab \(executingTabId)")
                executingTab.cachedResults = result.rows
                executingTab.cachedColumnNames = result.columnNames.isEmpty ? nil : result.columnNames

                // Also update via tabManager if this is still the active tab and same query
                if isStillActiveTab && isSameSavedQuery {
                    tabManager.updateActiveTabResults(
                        results: result.rows,
                        columnNames: result.columnNames.isEmpty ? nil : result.columnNames
                    )
                }

                // Cache results in-memory for the executing saved query (not current one)
                if let savedQueryId = executingSavedQueryId {
                    let columnNames = result.columnNames.isEmpty ? [] : result.columnNames
                    appState.query.cacheResults(for: savedQueryId, rows: result.rows, columnNames: columnNames)
                    if isSameSavedQuery {
                        appState.query.lastExecutedAt = Date()
                    }
                    DebugLog.print("💾 [QueryEditorViewModel] Cached \(result.rows.count) results in-memory for SavedQuery \(savedQueryId)")
                }
            }

            // Refresh tables list if query modified schema
            if isSchemaModifyingQuery(queryText) {
                await refreshTables(database: database)

                // Clear results if dropped table was the selected table
                if isDropTableQuery(queryText),
                   let selectedTable = appState.connection.selectedTable,
                   let droppedTable = tableName,
                   selectedTable.name.lowercased() == droppedTable.lowercased() {
                    DebugLog.print("🗑️ [QueryEditorViewModel] Dropped selected table, clearing results")
                    appState.connection.selectedTable = nil
                    appState.query.clearQueryResults()
                }
            }
        } else {
            // Handle error - update global state only if same query is still active
            if isStillActiveTab && isSameSavedQuery {
                appState.query.finishQueryExecution(with: result)

                // Show truncated error message
                let errorMessage = TarnError.extractDetailedMessage(result.error!)
                let truncatedError = errorMessage.count > 50
                    ? String(errorMessage.prefix(47)) + "..."
                    : errorMessage
                appState.query.setTemporaryStatus("Error: \(truncatedError)")
            }

            DebugLog.print("❌ [QueryEditorViewModel] Query execution failed: \(result.error!)")
        }
    }

    // MARK: - Explain Query Plan

    /// Run EXPLAIN QUERY PLAN and parse the result into a tree.
    func explainQuery() async {
        guard appState.connection.selectedDatabase != nil else {
            showNoDatabaseAlert = true
            return
        }

        let queryText = appState.query.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { return }

        let explainSQL = "EXPLAIN QUERY PLAN \(queryText)"

        appState.query.startQueryExecution()
        let result = await queryService.executeQuery(explainSQL, preferredColumnOrder: nil)
        appState.query.finishQueryExecution(with: result)

        if result.isSuccess {
            let nodes = EQPParser.parse(
                tableRows: result.rows,
                columnNames: result.columnNames
            )
            appState.query.queryPlanNodes = nodes
            appState.query.isShowingQueryPlan = !nodes.isEmpty
            let time = QueryState.formatExecutionTime(result.executionTime)
            appState.query.setTemporaryStatus("Explain completed in \(time)")
        }
    }

    // MARK: - Private Helpers

    private func refreshTables(database: DatabaseInfo) async {
        do {
            appState.connection.tables = try await appState.connection.databaseService.fetchTables(
                database: database.name
            )
            DebugLog.print("🔄 [QueryEditorViewModel] Tables list refreshed after schema change")
        } catch {
            DebugLog.print("⚠️ [QueryEditorViewModel] Failed to refresh tables: \(error)")
        }
    }

    private func isCancellationLike(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == "QueryService", nsError.code == -1 {
            return true
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("cancel")
    }
}
