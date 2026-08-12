//
//  TableListRowView.swift
//  PostgresGUI
//

import SwiftUI

// MARK: - Table Row View (Container)

struct TableListRowView: View {
    @Environment(AppState.self) private var appState

    let table: TableInfo
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void
    var showSchemaPrefix: Bool = true

    @State private var viewModel: TableContextMenuViewModel?
    @State private var isLoadingColumns = false

    /// Whether this table's columns are expanded
    private var isExpanded: Bool {
        appState.connection.expandedTables.contains(table.id)
    }

    /// Column info from cache or table
    private var columnInfo: [ColumnInfo]? {
        appState.connection.getColumnInfo(for: table)
    }

    var body: some View {
        TableListRowComponent(
            table: table,
            isExpanded: isExpanded,
            isExecutingQuery: isExecutingQuery,
            columnInfo: columnInfo,
            isLoadingColumns: isLoadingColumns,
            showSchemaPrefix: showSchemaPrefix,
            onToggleExpanded: {
                toggleExpanded()
            },
            onShowAllRows: {
                appState.requestTableQuery(for: table)
            },
            refreshQueryAction: {
                Task {
                    await refreshQueryAction(table)
                }
            },
            onGenerateDDL: {
                Task { @MainActor in
                    let vm = ensureViewModel()
                    await vm.generateDDL()
                }
            },
            onShowExport: {
                ensureViewModel().showExportSheet = true
            },
            onTruncate: {
                ensureViewModel().showTruncateConfirmation = true
            },
            onDrop: {
                ensureViewModel().showDropConfirmation = true
            }
        )
        .modifier(TableContextMenuModalsWrapper(viewModel: $viewModel))
    }

    // MARK: - Actions

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isExpanded {
                appState.connection.expandedTables.remove(table.id)
            } else {
                appState.connection.expandedTables.insert(table.id)
                // Fetch column info if not already cached
                if columnInfo == nil {
                    fetchColumnInfo()
                }
            }
        }
    }

    private func fetchColumnInfo() {
        isLoadingColumns = true
        Task { @MainActor in
            // Fetch column info and primary keys directly without requiring table to be "selected"
            // This bypasses TableMetadataService which has selection guards
            do {
                // Fetch both column info and primary keys in parallel
                async let columnsTask = appState.connection.databaseService.fetchColumnInfo(
                    schema: table.schema,
                    table: table.name
                )
                async let primaryKeysTask = appState.connection.databaseService.fetchPrimaryKeyColumns(
                    schema: table.schema,
                    table: table.name
                )

                var columns = try await columnsTask
                let primaryKeys = try await primaryKeysTask

                // Mark primary key columns
                let pkSet = Set(primaryKeys)
                for i in columns.indices {
                    if pkSet.contains(columns[i].name) {
                        columns[i].isPrimaryKey = true
                    }
                }

                // Cache the result
                appState.connection.tableMetadataCache[table.id] = (
                    primaryKeys: primaryKeys,
                    columns: columns
                )
            } catch {
                DebugLog.print("⚠️ [TableListRowView] Failed to fetch column info for \(table.name): \(error)")
            }
            isLoadingColumns = false
        }
    }

    /// Ensures the viewModel exists, creating it lazily if needed.
    /// Called when menu actions require the ViewModel.
    @MainActor
    private func ensureViewModel() -> TableContextMenuViewModel {
        if let existing = viewModel {
            return existing
        }
        let vm = TableContextMenuViewModel(table: table, appState: appState)
        viewModel = vm
        return vm
    }
}

// MARK: - Modals Wrapper

/// Wrapper to safely handle optional viewModel binding
struct TableContextMenuModalsWrapper: ViewModifier {
    @Binding var viewModel: TableContextMenuViewModel?

    func body(content: Content) -> some View {
        if let vm = viewModel {
            content.tableContextMenuModals(viewModel: vm) {
                // No additional action needed after drop - the ViewModel handles refresh
            }
        } else {
            content
        }
    }
}
