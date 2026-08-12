//
//  MainSplitView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftData
import SwiftUI

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SavedQuery.updatedAt, order: .reverse) private var savedQueries: [SavedQuery]
    @Query(sort: \QueryFolder.name) private var queryFolders: [QueryFolder]

    @State private var searchText: String = ""
    @State private var viewModel: DetailContentViewModel?
    @State private var selectedQueryIDs: Set<SavedQuery.ID> = []
    @State private var showHealthInspector: Bool = false

    /// Window title: shows the SQLite filename when a file is open, or the Postgres database name.
    private var navigationTitleText: String {
        if let sqliteProfile = appState.connection.activeConnection?.sqliteProfile {
            return sqliteProfile.displayName
        }
        return appState.connection.selectedDatabase?.name ?? ""
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            ConnectionsDatabasesSidebar()
                .navigationSplitViewColumnWidth(
                    min: Constants.ColumnWidth.sidebarMin,
                    ideal: Constants.ColumnWidth.sidebarIdeal,
                    max: Constants.ColumnWidth.sidebarMax
                )
        } detail: {
            VStack(spacing: 0) {
                if tabManager.tabs.count > 1 {
                    TabBarView()
                }

                VSplitView {
                    // Row 1: Query results or query plan
                    VStack(spacing: 0) {
                        if appState.query.isShowingQueryPlan {
                            QueryPlanPanel(nodes: appState.query.queryPlanNodes) {
                                appState.query.isShowingQueryPlan = false
                            }
                        } else if let viewModel = viewModel {
                            QueryResultsView(
                                searchText: searchText,
                                onDeleteKeyPressed: {
                                    viewModel.deleteSelectedRows()
                                },
                                onSpaceKeyPressed: {
                                    viewModel.openJSONView()
                                },
                                onJSONCellTapped: { column, value in
                                    viewModel.openCellJSONInspector(
                                        column: column,
                                        rawValue: value
                                    )
                                }
                            )
                        } else {
                            QueryResultsView(searchText: searchText)
                        }
                    }
                    .frame(minHeight: 300)

                    // Row 2: Queries list + Query editor
                    HSplitView {
                        // Column 1: Saved queries list
                        SavedQueriesSidebarSection(
                            savedQueries: savedQueries,
                            folders: queryFolders,
                            selectedQueryIDs: $selectedQueryIDs
                        )
                        .frame(minWidth: 200, maxWidth: 260)

                        // Column 2: Query editor
                        QueryEditorView()
                    }
                    .frame(minHeight: 250)
                }
            }
            .toolbar {
                if let viewModel = viewModel {
                    DetailContentToolbar(viewModel: viewModel)
                }
                // Health Inspector toolbar button — only shown when a SQLite file is open
                if appState.connection.activeConnection?.sqliteProfile != nil {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            showHealthInspector = true
                        } label: {
                            Label("Database Health", systemImage: "heart.text.square")
                        }
                        .help("Open the Database Health Inspector")
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    let rowOperations = RowOperationsService()
                    let queryService = QueryService(
                        databaseService: appState.connection.databaseService,
                        queryState: appState.query
                    )
                    viewModel = DetailContentViewModel(
                        appState: appState,
                        rowOperations: rowOperations,
                        queryService: queryService
                    )
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .searchable(text: $searchText, prompt: "Filter results")
        .modifier(DetailContentModalsWrapper(viewModel: viewModel))
        .sheet(isPresented: $showHealthInspector) {
            if let sqliteService = appState.connection.databaseService as? SQLiteDatabaseService {
                HealthInspectorView(service: sqliteService)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let toast = appState.query.mutationToast {
                MutationToastView(
                    data: toast,
                    onViewTable: {
                        // Find and select the table, then refresh its data
                        if let tableName = toast.tableName,
                            let table = appState.connection.tables.first(where: {
                                $0.name == tableName
                            })
                        {
                            let wasAlreadySelected = appState.connection.isTableStillSelected(table.id)
                            appState.connection.selectedTable = table

                            // Only explicitly execute if table was already selected
                            // (onChange in QueryResultsView won't fire if selectedTable didn't change)
                            if wasAlreadySelected {
                                appState.requestTableQuery(for: table)
                            }
                        }
                        appState.query.dismissMutationToast()
                    },
                    onDismiss: {
                        appState.query.dismissMutationToast()
                    }
                )
                .padding(20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.7),
            value: appState.query.mutationToast != nil)
    }
}

// Wrapper to handle optional viewModel for modals
struct DetailContentModalsWrapper: ViewModifier {
    var viewModel: DetailContentViewModel?
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        if let vm = viewModel {
            content.modifier(DetailContentModals(viewModel: vm))
        } else {
            content
        }
    }
}


