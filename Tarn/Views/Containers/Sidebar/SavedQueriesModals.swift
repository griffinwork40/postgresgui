//
//  SavedQueriesModals.swift
//  Tarn
//

import SwiftData
import SwiftUI

/// ViewModifier that owns all modal / dialog presentation for the saved-queries sidebar.
///
/// Extracted from `SavedQueriesSidebarSection` to keep both files under the 350-line ceiling.
/// No behaviour is changed — only the attachment site moved.
struct SavedQueriesModals: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let viewModel: SavedQueriesViewModel
    let folders: [QueryFolder]

    @Binding var selectedQueryIDs: Set<SavedQuery.ID>

    func body(content: Content) -> some View {
        content
            // MARK: Edit Query Sheet
            .sheet(
                item: Binding(
                    get: { viewModel.queryToEdit },
                    set: { viewModel.queryToEdit = $0 }
                )
            ) { query in
                EditQuerySheet(
                    initialName: query.name,
                    onSave: { newName in
                        query.name = newName
                        query.updatedAt = Date()
                        // Update toolbar if this is the currently selected query
                        if appState.query.currentSavedQueryId == query.id {
                            appState.query.currentQueryName = newName
                        }
                        viewModel.queryToEdit = nil
                    },
                    onCancel: {
                        viewModel.queryToEdit = nil
                    }
                )
            }
            // MARK: Edit Folder Sheet
            .sheet(
                item: Binding(
                    get: { viewModel.folderToEdit },
                    set: { viewModel.folderToEdit = $0 }
                )
            ) { folder in
                EditFolderSheet(
                    initialName: folder.name,
                    onSave: { newName in
                        folder.name = newName
                        folder.updatedAt = Date()
                        viewModel.folderToEdit = nil
                    },
                    onCancel: {
                        viewModel.folderToEdit = nil
                    }
                )
            }
            // MARK: Move to Folder Sheet
            .sheet(
                isPresented: Binding(
                    get: { !viewModel.queriesToMove.isEmpty },
                    set: { if !$0 { viewModel.queriesToMove = [] } }
                )
            ) {
                MoveToFolderSheet(
                    queryCount: viewModel.queriesToMove.count,
                    folders: folders,
                    currentFolderIds: Set(viewModel.queriesToMove.map { $0.folder?.id }),
                    onMoveToFolder: { folder in
                        for query in viewModel.queriesToMove {
                            query.folder = folder
                            query.updatedAt = Date()
                        }
                        viewModel.queriesToMove = []
                    },
                    onCreateFolderAndMove: { folderName in
                        let newFolder = QueryFolder(name: folderName)
                        modelContext.insert(newFolder)
                        for query in viewModel.queriesToMove {
                            query.folder = newFolder
                            query.updatedAt = Date()
                        }
                        viewModel.queriesToMove = []
                    },
                    onCancel: {
                        viewModel.queriesToMove = []
                    }
                )
            }
            // MARK: Delete Queries Confirmation
            .confirmationDialog(
                viewModel.queriesToDelete.count == 1
                    ? "Delete Query?" : "Delete \(viewModel.queriesToDelete.count) Queries?",
                isPresented: Binding(
                    get: { !viewModel.queriesToDelete.isEmpty },
                    set: { if !$0 { viewModel.queriesToDelete = [] } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteQueries(viewModel.queriesToDelete, modelContext: modelContext)
                    selectedQueryIDs = []
                }
                Button("Cancel", role: .cancel) {
                    viewModel.queriesToDelete = []
                }
            } message: {
                if viewModel.queriesToDelete.count == 1,
                    let query = viewModel.queriesToDelete.first
                {
                    Text(
                        "Are you sure you want to delete \"\(query.name)\"? This action cannot be undone."
                    )
                } else {
                    Text(
                        "Are you sure you want to delete \(viewModel.queriesToDelete.count) queries? This action cannot be undone."
                    )
                }
            }
            // MARK: Delete Single Folder Confirmation
            .confirmationDialog(
                "Delete Folder?",
                isPresented: Binding(
                    get: { viewModel.folderToDelete != nil },
                    set: { if !$0 { viewModel.folderToDelete = nil } }
                )
            ) {
                Button("Delete Folder Only", role: .destructive) {
                    if let folder = viewModel.folderToDelete {
                        viewModel.deleteFolder(
                            folder, deleteQueries: false, modelContext: modelContext)
                    }
                }
                Button("Delete Folder and Queries", role: .destructive) {
                    if let folder = viewModel.folderToDelete {
                        viewModel.deleteFolder(
                            folder, deleteQueries: true, modelContext: modelContext)
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.folderToDelete = nil
                }
            } message: {
                if let folder = viewModel.folderToDelete {
                    let queryCount = folder.queries?.count ?? 0
                    if queryCount > 0 {
                        Text(
                            "The folder \"\(folder.name)\" contains \(queryCount) queries. What would you like to do?"
                        )
                    } else {
                        Text(
                            "Are you sure you want to delete the folder \"\(folder.name)\"?"
                        )
                    }
                }
            }
            // MARK: Delete Multiple Folders Confirmation
            .confirmationDialog(
                viewModel.foldersToDelete.count == 1
                    ? "Delete Folder?" : "Delete \(viewModel.foldersToDelete.count) Folders?",
                isPresented: Binding(
                    get: { !viewModel.foldersToDelete.isEmpty },
                    set: { if !$0 { viewModel.foldersToDelete = [] } }
                )
            ) {
                Button("Delete Folders Only", role: .destructive) {
                    viewModel.deleteFolders(
                        viewModel.foldersToDelete, deleteQueries: false,
                        modelContext: modelContext)
                    for folder in viewModel.foldersToDelete {
                        selectedQueryIDs.remove(folder.id)
                    }
                }
                Button("Delete Folders and Queries", role: .destructive) {
                    viewModel.deleteFolders(
                        viewModel.foldersToDelete, deleteQueries: true,
                        modelContext: modelContext)
                    for folder in viewModel.foldersToDelete {
                        selectedQueryIDs.remove(folder.id)
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.foldersToDelete = []
                }
            } message: {
                let totalQueryCount = viewModel.foldersToDelete.reduce(0) {
                    $0 + ($1.queries?.count ?? 0)
                }
                if viewModel.foldersToDelete.count == 1,
                    let folder = viewModel.foldersToDelete.first
                {
                    if totalQueryCount > 0 {
                        Text(
                            "The folder \"\(folder.name)\" contains \(totalQueryCount) queries. What would you like to do?"
                        )
                    } else {
                        Text(
                            "Are you sure you want to delete the folder \"\(folder.name)\"?"
                        )
                    }
                } else {
                    if totalQueryCount > 0 {
                        Text(
                            "These \(viewModel.foldersToDelete.count) folders contain \(totalQueryCount) queries total. What would you like to do?"
                        )
                    } else {
                        Text(
                            "Are you sure you want to delete \(viewModel.foldersToDelete.count) folders?"
                        )
                    }
                }
            }
    }
}
