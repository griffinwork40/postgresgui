//
//  MainSplitViewPreview.swift
//  Tarn
//
//  Preview provider for MainSplitView, extracted to stay under LOC ceiling.
//

import SwiftUI
import SwiftData

private struct MainSplitViewPreview: View {
    @State private var appState = AppState()
    @State private var tabManager = TabManager()
    @State private var loadingState = LoadingState()
    @Environment(\.modelContext) private var modelContext
    @State private var didSeed = false

    var body: some View {
        MainSplitView()
            .environment(appState)
            .environment(tabManager)
            .environment(loadingState)
            .task {
                guard !didSeed else { return }
                didSeed = true
                seedPreviewData()
                tabManager.initialize(with: modelContext)
                loadingState.setReady()
            }
    }

    @MainActor
    private func seedPreviewData() {
        seedModelDataIfNeeded()
        seedAppState()
    }

    @MainActor
    private func seedModelDataIfNeeded() {
        let connections = (try? modelContext.fetch(FetchDescriptor<ConnectionProfile>())) ?? []
        let folders = (try? modelContext.fetch(FetchDescriptor<QueryFolder>())) ?? []
        let savedQueries = (try? modelContext.fetch(FetchDescriptor<SavedQuery>())) ?? []
        let tabs = (try? modelContext.fetch(FetchDescriptor<TabState>())) ?? []

        if connections.isEmpty {
            let mainConnection = ConnectionProfile(
                name: "Local Postgres",
                host: "localhost",
                port: 5432,
                username: "postgres",
                database: "postgres"
            )
            let analyticsConnection = ConnectionProfile(
                name: "Analytics",
                host: "analytics.internal",
                port: 5432,
                username: "reporting",
                database: "analytics"
            )
            modelContext.insert(mainConnection)
            modelContext.insert(analyticsConnection)
        }

        if folders.isEmpty {
            let folder = QueryFolder(name: "Favorites")
            modelContext.insert(folder)
        }

        if savedQueries.isEmpty {
            let folder = (try? modelContext.fetch(FetchDescriptor<QueryFolder>()))?.first
            let query1 = SavedQuery(
                name: "Top quotes",
                queryText: "select * from quotes order by created_at desc limit 100;",
                folder: folder
            )
            let query2 = SavedQuery(
                name: "Recent docs",
                queryText: "select id, created_at from docs order by created_at desc limit 50;",
                folder: folder
            )
            modelContext.insert(query1)
            modelContext.insert(query2)
        }

        if tabs.isEmpty {
            let connection = (try? modelContext.fetch(FetchDescriptor<ConnectionProfile>()))?.first
            let activeTab = TabState(
                connectionId: connection?.id,
                databaseName: "postgres",
                queryText: "select * from quotes limit 100;",
                isActive: true,
                order: 0
            )
            modelContext.insert(activeTab)

            let secondTab = TabState(
                connectionId: connection?.id,
                databaseName: "analytics",
                queryText: "select * from events order by created_at desc limit 50;",
                isActive: false,
                order: 1
            )
            modelContext.insert(secondTab)

            let thirdTab = TabState(
                connectionId: connection?.id,
                databaseName: "postgres",
                queryText: "select count(*) from documents;",
                isActive: false,
                order: 2
            )
            modelContext.insert(thirdTab)
        }
    }

    @MainActor
    private func seedAppState() {
        let sampleConnection = ConnectionProfile(
            name: "Local Postgres",
            host: "localhost",
            port: 5432,
            username: "postgres",
            database: "postgres"
        )
        appState.connection.currentConnection = sampleConnection
        appState.connection.databases = [
            DatabaseInfo(name: "postgres", tableCount: 42),
            DatabaseInfo(name: "analytics", tableCount: 18)
        ]
        appState.connection.schemas = ["public", "analytics"]
        appState.connection.selectedDatabase = DatabaseInfo(name: "postgres", tableCount: 42)

        let columns: [ColumnInfo] = [
            ColumnInfo(name: "id", dataType: "uuid", isPrimaryKey: true),
            ColumnInfo(name: "doc_id", dataType: "varchar"),
            ColumnInfo(name: "content", dataType: "text"),
            ColumnInfo(name: "created_at", dataType: "timestamp")
        ]

        let tables: [TableInfo] = [
            TableInfo(name: "quotes", schema: "public", columnInfo: columns),
            TableInfo(name: "documents", schema: "public"),
            TableInfo(name: "events", schema: "analytics"),
            TableInfo(name: "sessions", schema: "analytics")
        ]

        appState.connection.tables = tables
        appState.connection.selectedSchema = nil
        appState.connection.selectedTable = tables.first
        appState.connection.expandedSchemas = ["public", "analytics"]
        if let firstTable = tables.first {
            appState.connection.expandedTables = [firstTable.id]
        }

        appState.query.queryColumnNames = ["id", "doc_id", "content", "created_at"]
        appState.query.queryResults = [
            TableRow(values: [
                "id": "4f2b6d9c-7c74-4c2a-b740-1e6b8b6f61bb",
                "doc_id": "doc_1289",
                "content": "Make small decisions quickly.",
                "created_at": "2026-01-29 12:34:56"
            ]),
            TableRow(values: [
                "id": "a4c91a2e-1a9a-4e6f-9a53-5ef49aa0b12e",
                "doc_id": "doc_1290",
                "content": "Ship, then iterate.",
                "created_at": "2026-01-29 12:36:10"
            ]),
            TableRow(values: [
                "id": "8a3ef8a9-1b8c-4f2c-8b63-5e45b2a2a4a1",
                "doc_id": "doc_1291",
                "content": "Keep the UI snappy.",
                "created_at": "2026-01-29 12:40:02"
            ])
        ]
        appState.query.showQueryResults = true
        appState.query.currentPage = 0
        appState.query.hasNextPage = true
    }
}

#Preview {
    MainSplitViewPreview()
        .modelContainer(
            for: [ConnectionProfile.self, SavedQuery.self, QueryFolder.self, TabState.self],
            inMemory: true
        )
        .frame(minWidth: 1100, minHeight: 800)
}
