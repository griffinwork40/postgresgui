//
//  SavedQueriesSidebarSection.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftData
import SwiftUI

/// Sidebar section for saved queries with folder support
struct SavedQueriesSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    let savedQueries: [SavedQuery]
    let folders: [QueryFolder]

    @Binding var selectedQueryIDs: Set<SavedQuery.ID>
    @State private var viewModel: SavedQueriesViewModel?

    /// IDs in selection that match actual queries
    private var selectedQueries: [SavedQuery] {
        savedQueries.filter { selectedQueryIDs.contains($0.id) }
    }

    /// IDs in selection that match folders (not queries)
    private var selectedFolders: [QueryFolder] {
        folders.filter { selectedQueryIDs.contains($0.id) }
    }

    /// Count of actual queries selected (excludes folder IDs)
    private var selectedQueryCount: Int {
        selectedQueries.count
    }

    /// Count of folders selected
    private var selectedFolderCount: Int {
        selectedFolders.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel = viewModel {
                // Header group: Title + Search
                VStack(spacing: 8) {
                    // Title
                    HStack {
                        Text("Queries")
                            .font(.headline)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 12)

                    // Search and sort header
                    searchAndSortHeader(viewModel: viewModel)
                }

                queryList(viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SavedQueriesViewModel(appState: appState)
            }
            // Sync initial selection from restored saved query
            if let savedQueryId = appState.query.currentSavedQueryId {
                selectedQueryIDs = [savedQueryId]
                // Auto-expand folder containing this query
                if let query = savedQueries.first(where: { $0.id == savedQueryId }) {
                    viewModel?.expandFolderContaining(query)
                }
            }
        }
    }

    // MARK: - Search and Sort Header

    @ViewBuilder
    private func searchAndSortHeader(viewModel: SavedQueriesViewModel) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField(
                    "Filter queries",
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.searchText = $0 }
                    )
                )
                .font(.system(size: 12))
                .textFieldStyle(.plain)

                sortMenu(viewModel: viewModel)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(Color.secondary, lineWidth: 0.5)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    .clipShape(Capsule())
            )
            .clipShape(Capsule())

            addQueryButton(viewModel: viewModel)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Add Query Button

    @ViewBuilder
    private func addQueryButton(viewModel: SavedQueriesViewModel) -> some View {
        Button {
            viewModel.createNewQuery(
                savedQueries: savedQueries, modelContext: modelContext)
            if let newQueryId = appState.query.currentSavedQueryId {
                selectedQueryIDs = [newQueryId]
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .glassEffect(.regular.interactive())
        .clipShape(Circle())
    }

    // MARK: - Sort Menu

    @ViewBuilder
    private func sortMenu(viewModel: SavedQueriesViewModel) -> some View {
        Menu {
            ForEach(QuerySortOption.allCases, id: \.self) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    HStack {
                        Label(option.rawValue, systemImage: option.icon)
                        if viewModel.sortOption == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Query List

    @ViewBuilder
    private func queryList(viewModel: SavedQueriesViewModel) -> some View {
        let hasContent = viewModel.hasAnyContent(savedQueries: savedQueries, folders: folders)
        let hasMatching = viewModel.hasMatchingContent(savedQueries: savedQueries, folders: folders)
        let filteredFolders = viewModel.filteredFolders(from: folders, savedQueries: savedQueries)
        let unfolderedQueries = viewModel.unfolderedQueries(from: savedQueries)

        List(selection: $selectedQueryIDs) {
            if !hasContent {
                Text("No saved queries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !hasMatching {
                Text("No matching queries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Folders with their queries
                ForEach(filteredFolders) { folder in
                    folderDisclosureGroup(folder: folder, viewModel: viewModel)
                }

                // Queries not in any folder
                ForEach(viewModel.filteredAndSorted(unfolderedQueries)) { query in
                    queryRow(query: query, viewModel: viewModel)
                        .listRowSeparator(.visible)
                }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .onDeleteCommand {
            guard !selectedQueryIDs.isEmpty else { return }
            viewModel.prepareToDeleteSelected(
                selectedQueryIDs: selectedQueryIDs,
                savedQueries: savedQueries
            )
        }
        .onChange(of: selectedQueryIDs) { oldIDs, newIDs in
            viewModel.handleSelectionChange(
                oldIDs: oldIDs,
                newIDs: newIDs,
                savedQueries: savedQueries,
                folders: folders
            )
            // Update tab's savedQueryId based on selection
            if newIDs.isEmpty && !oldIDs.isEmpty {
                tabManager.clearActiveTabSavedQueryId()
            } else if newIDs.count == 1, let selectedId = newIDs.first {
                tabManager.updateActiveTab(savedQueryId: selectedId)
            }
        }
        .onChange(of: appState.query.currentSavedQueryId) { _, newID in
            selectedQueryIDs = viewModel.handleCurrentQueryIdChange(
                newID: newID,
                savedQueries: savedQueries
            )
        }
        .modifier(
            SavedQueriesModals(
                viewModel: viewModel,
                folders: folders,
                selectedQueryIDs: $selectedQueryIDs
            )
        )
    }

    // MARK: - Folder Disclosure Group

    @ViewBuilder
    private func folderDisclosureGroup(folder: QueryFolder, viewModel: SavedQueriesViewModel)
        -> some View
    {
        DisclosureGroup(
            isExpanded: Binding(
                get: { viewModel.expandedFolders.contains(folder.id) },
                set: { _ in viewModel.toggleFolderExpansion(folder) }
            )
        ) {
            let folderQueries = viewModel.filteredAndSorted(folder.queries ?? [])
            ForEach(folderQueries) { query in
                queryRow(query: query, viewModel: viewModel)
                    .listRowSeparator(.visible)
            }
        } label: {
            QueryFolderRowView(
                folder: folder,
                onRename: { viewModel.folderToEdit = folder },
                onDelete: { viewModel.folderToDelete = folder }
            )
        }
    }

    // MARK: - Query Row

    @ViewBuilder
    private func queryRow(query: SavedQuery, viewModel: SavedQueriesViewModel) -> some View {
        SavedQueryRowView(
            query: query,
            isSelected: selectedQueryIDs.contains(query.id),
            selectedQueryCount: selectedQueryCount,
            selectedFolderCount: selectedFolderCount,
            onEdit: { viewModel.queryToEdit = query },
            onDelete: { viewModel.queriesToDelete = [query] },
            onDeleteSelectedQueries: {
                viewModel.prepareToDeleteSelected(
                    selectedQueryIDs: selectedQueryIDs,
                    savedQueries: savedQueries
                )
            },
            onDeleteSelectedFolders: {
                viewModel.prepareToDeleteSelectedFolders(
                    selectedFolders: selectedFolders
                )
            },
            onDuplicate: {
                viewModel.duplicateQuery(query, modelContext: modelContext)
            },
            onMoveToFolder: {
                viewModel.prepareToMoveQueries(
                    query: query,
                    selectedQueryIDs: selectedQueryIDs,
                    savedQueries: savedQueries
                )
            }
        )
    }
}
