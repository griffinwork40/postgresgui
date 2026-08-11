//
//  TableMetadataResolver.swift
//  PostgresGUI
//
//  Extracted from AppState.swift — owns table metadata fetching,
//  column order resolution, and the metadata cache lifecycle.
//

import Foundation

@Observable
@MainActor
final class TableMetadataResolver {
    // MARK: - Dependencies

    private let connection: ConnectionState
    private let service: TableMetadataServiceProtocol

    // MARK: - Task State

    private var metadataTask: Task<Void, Never>?

    // MARK: - Init

    init(
        connection: ConnectionState,
        service: TableMetadataServiceProtocol? = nil
    ) {
        self.connection = connection
        self.service = service ?? TableMetadataService()
    }

    // MARK: - Public API

    /// Whether metadata needs fetching for the given table.
    func shouldFetch(for table: TableInfo) -> Bool {
        guard let cached = connection.tableMetadataCache[table.id] else {
            return true
        }
        return cached.primaryKeys == nil || cached.columns == nil
    }

    /// Cached column order (no async round-trip). Returns nil if not cached.
    func cachedColumnOrder(for table: TableInfo) -> [String]? {
        guard let cachedColumns = connection.getColumnInfo(for: table),
              !cachedColumns.isEmpty else {
            return nil
        }
        return cachedColumns.map { $0.name }
    }

    /// Start an async metadata fetch in a background Task.
    func startFetch(
        for table: TableInfo,
        tableId: String,
        databaseId: String?,
        connectionId: UUID?
    ) {
        metadataTask?.cancel()
        metadataTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard connection.isQueryContextValid(
                tableId: tableId,
                databaseId: databaseId,
                connectionId: connectionId
            ) else {
                return
            }
            await fetchMetadata(for: table)
        }
    }

    /// Cancel in-flight metadata fetch.
    func cancel() {
        metadataTask?.cancel()
    }

    /// Resolve column order for a table, fetching metadata if not cached.
    func preferredColumnOrder(for table: TableInfo) async -> [String]? {
        if let cachedColumns = connection.getColumnInfo(for: table),
           !cachedColumns.isEmpty {
            return cachedColumns.map { $0.name }
        }

        let expectedConnectionId = connection.currentConnection?.id
        let expectedDatabaseId = connection.selectedDatabase?.id

        do {
            let columns = try await connection.databaseService.fetchColumnInfo(
                schema: table.schema,
                table: table.name
            )

            guard connection.currentConnection?.id == expectedConnectionId,
                  connection.selectedDatabase?.id == expectedDatabaseId else {
                DebugLog.print("⚠️ [MetadataResolver] Skipping column order cache for \(table.id) due to context change")
                return nil
            }

            let existingCache = connection.tableMetadataCache[table.id]
            connection.tableMetadataCache[table.id] = (
                primaryKeys: existingCache?.primaryKeys,
                columns: columns
            )

            return columns.map { $0.name }
        } catch {
            DebugLog.print("⚠️ [MetadataResolver] Failed to fetch column order for \(table.name): \(error)")
            return nil
        }
    }

    /// Resolve column order by table name, using schema context to disambiguate.
    func preferredColumnOrder(forTableName tableName: String?) async -> [String]? {
        guard let tableName else {
            DebugLog.print("🧭 [MetadataResolver] preferredColumnOrder: missing tableName")
            return nil
        }

        if let selectedTable = connection.selectedTable,
           selectedTable.name.caseInsensitiveCompare(tableName) == .orderedSame {
            DebugLog.print("🧭 [MetadataResolver] preferredColumnOrder: using selected table \(selectedTable.name)")
            return await preferredColumnOrder(for: selectedTable)
        }

        let matchesByName = connection.tables.filter {
            $0.name.caseInsensitiveCompare(tableName) == .orderedSame
        }

        if matchesByName.isEmpty {
            DebugLog.print("🧭 [MetadataResolver] preferredColumnOrder: no table match for \(tableName)")
            return nil
        }

        let scopedMatches: [TableInfo]
        if let selectedSchema = connection.selectedSchema {
            let schemaScopedMatches = matchesByName.filter { $0.schema == selectedSchema }
            scopedMatches = schemaScopedMatches.isEmpty ? matchesByName : schemaScopedMatches
        } else {
            scopedMatches = matchesByName
        }

        let resolvedTable: TableInfo?
        if scopedMatches.count == 1 {
            resolvedTable = scopedMatches[0]
        } else if let publicMatch = scopedMatches.first(where: { $0.schema == "public" }) {
            resolvedTable = publicMatch
        } else {
            resolvedTable = scopedMatches.first
        }

        guard let table = resolvedTable else {
            DebugLog.print("🧭 [MetadataResolver] preferredColumnOrder: could not resolve table for \(tableName)")
            return nil
        }

        DebugLog.print("🧭 [MetadataResolver] preferredColumnOrder: using resolved table \(table.schema).\(table.name)")
        return await preferredColumnOrder(for: table)
    }

    // MARK: - Private

    private func fetchMetadata(for table: TableInfo) async {
        _ = await service.fetchAndCacheMetadata(
            for: table,
            connectionState: connection,
            databaseService: connection.databaseService
        )
    }
}
