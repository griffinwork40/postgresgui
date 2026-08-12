//
//  TableMetadataServiceProtocol.swift
//  Tarn
//
//  Protocol abstraction for table metadata fetching and caching operations.
//  Enables dependency injection and testability.
//

import Foundation

/// Protocol defining table metadata operations
@MainActor
protocol TableMetadataServiceProtocol {
    /// Fetch and cache table metadata (primary keys and column info)
    /// Handles race conditions by checking if table is still selected
    func fetchAndCacheMetadata(
        for table: TableInfo,
        connectionState: ConnectionState,
        databaseService: DatabaseServiceProtocol
    ) async -> (primaryKeys: [String]?, columnInfo: [ColumnInfo]?)?

    /// Update the selected table with metadata if not already set
    /// Also updates the metadata cache
    func updateSelectedTableMetadata(
        connectionState: ConnectionState,
        primaryKeys: [String]?,
        columnInfo: [ColumnInfo]?
    )
}
