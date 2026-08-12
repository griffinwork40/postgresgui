//
//  TablesListView.swift
//  Tarn
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

// Legacy wrapper - kept for compatibility
struct TablesListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
}

// Isolated view that only depends on explicit parameters, not AppState environment
struct TablesListIsolated: View {
    let tables: [TableInfo]
    let groupedTables: [SchemaGroup]
    let selectedSchema: String?  // nil means "All Schemas"
    @Binding var selectedTable: TableInfo?
    @Binding var expandedSchemas: Set<String>
    let isLoadingTables: Bool
    let isShowingRefreshFeedback: Bool
    let isExecutingQuery: Bool
    let selectedDatabase: DatabaseInfo?

    let refreshQueryAction: (TableInfo) async -> Void

    /// Number of tables to load per batch for incremental rendering
    private static let batchSize = 100

    /// Current number of tables to display (for incremental loading)
    @State private var displayedCount: Int = TablesListIsolated.batchSize

    /// Whether to show grouped view (multiple schemas present)
    private var shouldShowGrouped: Bool {
        groupedTables.count > 1
    }

    /// Tables to display (limited for performance)
    private var displayedTables: ArraySlice<TableInfo> {
        tables.prefix(displayedCount)
    }

    /// Whether there are more tables to load
    private var hasMoreTables: Bool {
        displayedCount < tables.count
    }

    private var shouldShowLoadingIndicator: Bool {
        isLoadingTables && tables.isEmpty
    }

    private var shouldShowRefreshOverlay: Bool {
        isShowingRefreshFeedback || (isLoadingTables && !tables.isEmpty)
    }

    var body: some View {
        let _ = {
            DebugLog.print(
                "🔍 [TablesListView] Body computed - " +
                "isLoadingTables: \(isLoadingTables), " +
                "refreshFeedback: \(isShowingRefreshFeedback), " +
                "effectiveLoading: \(shouldShowLoadingIndicator), " +
                "tablesCount: \(tables.count), " +
                "selectedTable: \(selectedTable?.name ?? "nil"), " +
                "grouped: \(shouldShowGrouped)"
            )
        }()

        baseContent
        .onChange(of: tables.count) { _, _ in
            // Reset displayed count when tables change (e.g., schema filter changed)
            displayedCount = Self.batchSize
        }
        .onChange(of: selectedSchema) { _, _ in
            // Reset displayed count when schema filter changes
            displayedCount = Self.batchSize
        }
    }

    @ViewBuilder
    private var baseContent: some View {
        if tables.isEmpty {
            if shouldShowLoadingIndicator {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if shouldShowGrouped {
            tablesContentWithRefreshOverlay {
                groupedTablesList
            }
        } else {
            tablesContentWithRefreshOverlay {
                flatTablesList
            }
        }
    }

    // MARK: - Flat List (single schema or filtered)

    private var flatTablesList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(displayedTables, id: \.id) { table in
                TableListRowView(
                    table: table,
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction,
                    showSchemaPrefix: selectedSchema == nil
                )
                .padding(.vertical, 2)
                .padding(.leading, 6)
            }

            // "Load more" button when there are more tables to show
            if hasMoreTables {
                loadMoreButton
            }
        }
    }

    private func tablesContentWithRefreshOverlay<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            ScrollView {
                content()
                    .padding(.top, shouldShowGrouped ? 12 : 8)
                    .padding(.bottom, 8)
            }

            if shouldShowRefreshOverlay {
                refreshOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: shouldShowRefreshOverlay)
    }

    private var refreshOverlay: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .opacity(0.45)

            ProgressView()
                .controlSize(.regular)
        }
        .contentShape(Rectangle())
    }

    private var loadMoreButton: some View {
        Button {
            displayedCount = min(displayedCount + Self.batchSize, tables.count)
        } label: {
            HStack {
                Spacer()
                Text("Load more (\(tables.count - displayedCount) remaining)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouped List (multiple schemas)

    private var groupedTablesList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedTables) { group in
                SchemaGroupView(
                    group: group,
                    isExpanded: Binding(
                        get: { expandedSchemas.contains(group.name) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedSchemas.insert(group.name)
                            } else {
                                expandedSchemas.remove(group.name)
                            }
                        }
                    ),
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction
                )
            }
        }
    }
}

