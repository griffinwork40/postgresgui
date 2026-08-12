//
//  QueryFolderManager.swift
//  PostgresGUI
//
//  Folder mutation operations extracted from SavedQueriesViewModel.
//

import Foundation
import SwiftData

// MARK: - Folder Expansion

extension SavedQueriesViewModel {

    func toggleFolderExpansion(_ folder: QueryFolder) {
        if expandedFolders.contains(folder.id) {
            expandedFolders.remove(folder.id)
            DebugLog.print("📁 [SavedQueriesViewModel] Collapsed folder: \(folder.name)")
        } else {
            expandedFolders.insert(folder.id)
            DebugLog.print("📂 [SavedQueriesViewModel] Expanded folder: \(folder.name)")
        }
    }

    func expandFolderContaining(_ query: SavedQuery) {
        if let folder = query.folder {
            expandedFolders.insert(folder.id)
        }
    }

    // MARK: - Folder Deletion

    func prepareToDeleteSelectedFolders(
        selectedFolders: [QueryFolder]
    ) {
        foldersToDelete = selectedFolders
        DebugLog.print("🗑️ [SavedQueriesViewModel] Preparing to delete \(selectedFolders.count) folders: \(selectedFolders.map { $0.name }.joined(separator: ", "))")
    }

    func deleteFolder(_ folder: QueryFolder, deleteQueries: Bool, modelContext: ModelContext) {
        deleteFolders([folder], deleteQueries: deleteQueries, modelContext: modelContext)
        folderToDelete = nil
    }

    func deleteFolders(_ folders: [QueryFolder], deleteQueries: Bool, modelContext: ModelContext) {
        for folder in folders {
            if deleteQueries {
                // Delete all queries in the folder
                for query in folder.queries ?? [] {
                    if appState.query.currentSavedQueryId == query.id {
                        appState.query.currentSavedQueryId = nil
                        appState.query.lastSavedAt = nil
                        appState.query.currentQueryName = nil
                    }
                    modelContext.delete(query)
                }
            } else {
                // Move queries out of the folder
                for query in folder.queries ?? [] {
                    query.folder = nil
                }
            }
            modelContext.delete(folder)
        }

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesViewModel] Deleted \(folders.count) folders")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to delete folders: \(error)")
        }

        foldersToDelete = []
    }
}
