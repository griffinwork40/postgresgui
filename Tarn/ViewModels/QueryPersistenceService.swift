//
//  QueryPersistenceService.swift
//  Tarn
//
//  Extracted from QueryEditorViewModel — handles auto-save persistence
//  of query text to SwiftData (SavedQuery create/update).
//

import Foundation
import SwiftData

@MainActor
final class QueryPersistenceService {
    private let appState: AppState
    private let tabManager: TabManager
    private let modelContext: ModelContext

    init(appState: AppState, tabManager: TabManager, modelContext: ModelContext) {
        self.appState = appState
        self.tabManager = tabManager
        self.modelContext = modelContext
    }

    /// Save with retry and surface errors via the returned tuple.
    func saveWithRetry() async -> (success: Bool, errorMessage: String?) {
        let maxRetries = 2
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try save()
                DebugLog.print("💾 [QueryPersistence] Auto-save successful")
                return (true, nil)
            } catch {
                lastError = error
                DebugLog.print("❌ [QueryPersistence] Save attempt \(attempt)/\(maxRetries) failed: \(error)")
                if attempt < maxRetries {
                    DebugLog.print("💾 [QueryPersistence] Retrying save in 100ms...")
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        DebugLog.print("❌ [QueryPersistence] All save attempts failed")
        return (false, lastError?.localizedDescription)
    }

    private func save() throws {
        let queryText = appState.query.queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !queryText.isEmpty else {
            DebugLog.print("💾 [QueryPersistence] Save skipped - empty query")
            return
        }

        let now = Date()
        var savedQueryName: String?

        if let existingId = appState.query.currentSavedQueryId {
            let descriptor = FetchDescriptor<SavedQuery>(
                predicate: #Predicate { $0.id == existingId }
            )
            if let existingQuery = try? modelContext.fetch(descriptor).first {
                existingQuery.queryText = queryText
                existingQuery.updatedAt = now
                savedQueryName = existingQuery.name
                DebugLog.print("💾 [QueryPersistence] Updated existing query: \(existingQuery.name)")
            }
        } else {
            let queryName = SavedQuery.generateName(from: queryText)
            let savedQuery = SavedQuery(
                name: queryName,
                queryText: queryText,
                connectionId: appState.connection.currentConnection?.id,
                databaseName: appState.connection.selectedDatabase?.name
            )
            modelContext.insert(savedQuery)

            appState.query.currentSavedQueryId = savedQuery.id
            savedQueryName = queryName

            tabManager.updateActiveTab(savedQueryId: savedQuery.id)

            DebugLog.print("💾 [QueryPersistence] Saved new query: \(queryName)")
        }

        appState.query.lastSavedAt = now
        appState.query.currentQueryName = savedQueryName

        try modelContext.save()
        DebugLog.print("💾 [QueryPersistence] Context saved to SwiftData")
    }
}
