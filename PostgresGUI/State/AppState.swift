//
//  AppState.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//
//  Composition root: wires sub-state objects and coordinators together.
//  All async lifecycle, debounce, and pagination machinery lives in
//  TableBrowseCoordinator, TableMetadataResolver, and SchemaContextManager.
//

import SwiftUI

@Observable
@MainActor
class AppState {
    // MARK: - Composed State Managers

    let navigation: NavigationState
    let connection: ConnectionState
    let query: QueryState

    // MARK: - Coordinators

    let tableBrowse: TableBrowseCoordinator
    let metadataResolver: TableMetadataResolver
    let schemaContext: SchemaContextManager

    // MARK: - Tab Manager (for caching query results)

    weak var tabManager: TabManager? {
        didSet { tableBrowse.setTabManager(tabManager) }
    }

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil,
        tableMetadataService: TableMetadataServiceProtocol? = nil
    ) {
        let nav = navigation ?? NavigationState()
        let conn = connection ?? ConnectionState()
        let q = query ?? QueryState()
        let resolver = TableMetadataResolver(
            connection: conn,
            service: tableMetadataService
        )

        self.navigation = nav
        self.connection = conn
        self.query = q
        self.metadataResolver = resolver
        self.tableBrowse = TableBrowseCoordinator(
            connection: conn,
            query: q,
            metadataResolver: resolver
        )
        self.schemaContext = SchemaContextManager(connection: conn)
    }

    // MARK: - Convenience Methods

    func showFileOpen() {
        navigation.showFileOpen()
    }

    func showDiscovery() {
        navigation.showDiscovery()
    }

    // MARK: - Query Execution (forwarding)

    func requestTableQuery(for table: TableInfo, limit: Int? = nil) {
        tableBrowse.requestTableQuery(for: table, limit: limit)
    }

    func requestPaginatedTableQuery(for table: TableInfo, targetPage: Int) {
        tableBrowse.requestPaginatedTableQuery(for: table, targetPage: targetPage)
    }

    func executeTableQuery(for table: TableInfo, limit: Int? = nil) async {
        await tableBrowse.executeTableQuery(for: table, limit: limit)
    }

    // MARK: - Column Order Resolution (forwarding)

    func preferredColumnOrder(for table: TableInfo) async -> [String]? {
        await metadataResolver.preferredColumnOrder(for: table)
    }

    func preferredColumnOrder(forTableName tableName: String?) async -> [String]? {
        await metadataResolver.preferredColumnOrder(forTableName: tableName)
    }

    // MARK: - Schema Context (forwarding)

    func setSchemaSearchPathDebounced(_ schema: String?) {
        schemaContext.setSchemaSearchPathDebounced(schema)
    }

    func setSchemaSearchPath(_ schema: String?) async {
        await schemaContext.setSchemaSearchPath(schema)
    }

    // MARK: - Cleanup

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard connection.isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up...")

        query.cleanup()
        tableBrowse.cancel()
        metadataResolver.cancel()
        schemaContext.cancel()

        await connection.cleanupOnWindowClose()

        DebugLog.print("✅ Cleanup completed")
    }
}
