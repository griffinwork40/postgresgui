//
//  TableBrowseCoordinator.swift
//  PostgresGUI
//
//  Extracted from AppState.swift — owns the table query dispatch lifecycle:
//  debounce, request-ID tracking, cancellation, execution pipeline,
//  pagination cache hits, and result compaction.
//

import SwiftUI

@Observable
@MainActor
final class TableBrowseCoordinator {
    // MARK: - Dependencies

    private let connection: ConnectionState
    private let query: QueryState
    private let metadataResolver: TableMetadataResolver
    private weak var tabManager: TabManager?

    // MARK: - Dispatch State

    private var tableQueryTask: Task<Void, Never>?
    private var tableQueryRequestId: Int = 0
    private let debounceNanoseconds: UInt64 = 120_000_000

    // MARK: - Init

    init(
        connection: ConnectionState,
        query: QueryState,
        metadataResolver: TableMetadataResolver,
        tabManager: TabManager? = nil
    ) {
        self.connection = connection
        self.query = query
        self.metadataResolver = metadataResolver
        self.tabManager = tabManager
    }

    func setTabManager(_ tabManager: TabManager?) {
        self.tabManager = tabManager
    }

    // MARK: - Public API

    /// Request a table query with debounce. Cancels any in-flight table query task.
    func requestTableQuery(for table: TableInfo, limit: Int? = nil) {
        let shouldInterrupt = hasInFlightLoadToSupersede()
        tableQueryTask?.cancel()
        metadataResolver.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        startLoading(for: table)
        connection.selectedTable = table

        tableQueryTask = Task { @MainActor in
            if shouldInterrupt {
                await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
            }
            guard isRequestCurrent(requestId) else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard isRequestCurrent(requestId) else { return }
            await executeInternal(
                for: table,
                limit: limit,
                requestId: requestId,
                applyCompaction: true,
                targetPage: nil
            )
        }
    }

    /// Request a paginated table query. Uses cached pages when available.
    func requestPaginatedTableQuery(for table: TableInfo, targetPage: Int) {
        guard targetPage >= 0 else { return }

        let shouldInterrupt = hasInFlightLoadToSupersede()
        tableQueryTask?.cancel()
        metadataResolver.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        connection.selectedTable = table

        let cacheContext = makePageCacheContext(
            tableId: table.id,
            databaseId: connection.selectedDatabase?.id,
            connectionId: connection.currentConnection?.id
        )
        if let cached = query.cachedTableBrowsePage(for: targetPage, context: cacheContext) {
            if shouldInterrupt {
                tableQueryTask = Task { @MainActor in
                    guard isRequestCurrent(requestId) else { return }
                    await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
                }
            } else {
                tableQueryTask = nil
            }
            applyCachedPage(cached, table: table, targetPage: targetPage)
            return
        }

        startLoading(for: table)
        tableQueryTask = Task { @MainActor in
            if shouldInterrupt {
                await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
            }
            guard isRequestCurrent(requestId) else { return }
            await executeInternal(
                for: table,
                limit: nil,
                requestId: requestId,
                applyCompaction: true,
                targetPage: targetPage
            )
        }
    }

    /// Direct execution (no debounce). Used by non-sidebar paths.
    func executeTableQuery(for table: TableInfo, limit: Int? = nil) async {
        tableQueryTask?.cancel()
        tableQueryTask = nil
        metadataResolver.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        startLoading(for: table)
        await executeInternal(
            for: table,
            limit: limit,
            requestId: requestId,
            applyCompaction: limit == nil,
            targetPage: nil
        )
    }

    /// Cancel all in-flight work.
    func cancel() {
        tableQueryTask?.cancel()
    }

    // MARK: - Execution Pipeline

    private func executeInternal(
        for table: TableInfo,
        limit: Int?,
        requestId: Int,
        applyCompaction: Bool,
        targetPage: Int?
    ) async {
        defer { finishLoadingIfCurrent(requestId) }

        guard isRequestCurrent(requestId) else { return }

        let tableId = table.id
        let databaseId = connection.selectedDatabase?.id
        let connectionId = connection.currentConnection?.id

        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        guard isRequestCurrent(requestId) else { return }

        query.startQueryExecution()

        let effectiveLimit: Int
        let isPaginated: Bool
        if let customLimit = limit {
            effectiveLimit = customLimit
            isPaginated = false
        } else {
            effectiveLimit = query.rowsPerPage + 1
            isPaginated = true
        }
        let requestedPage = isPaginated ? max(targetPage ?? query.currentPage, 0) : 0

        let preferredColumnOrder = metadataResolver.cachedColumnOrder(for: table)

        guard isRequestCurrent(requestId) else { return }

        let result = await queryService.executeTableQuery(
            for: table,
            limit: effectiveLimit,
            offset: isPaginated ? calculateOffset(page: requestedPage, pageSize: query.rowsPerPage) : 0,
            preferredColumnOrder: preferredColumnOrder
        )

        guard isRequestCurrent(requestId) else {
            DebugLog.print("⚠️ [TableBrowse] Query for \(table.name) superseded/cancelled, skipping state update")
            return
        }

        guard requestId == tableQueryRequestId else {
            DebugLog.print("⚠️ [TableBrowse] Query for \(table.name) superseded (newer request), skipping state update")
            return
        }

        guard connection.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [TableBrowse] Query for \(table.name) superseded (context changed), skipping state update")
            query.isExecutingQuery = false
            return
        }

        if result.isSuccess {
            var resultRows = result.rows
            if applyCompaction {
                resultRows = await TableBrowseResultCompactor.compactRowsOffMain(
                    rows: result.rows,
                    maxCellCharacters: Constants.tableBrowseMaxCellCharacters,
                    truncationSuffix: Constants.tableBrowseTruncationSuffix
                )

                guard isRequestCurrent(requestId) else { return }

                guard connection.isQueryContextValid(
                    tableId: tableId,
                    databaseId: databaseId,
                    connectionId: connectionId
                ) else {
                    DebugLog.print("⚠️ [TableBrowse] Query for \(table.name) superseded after compaction, skipping state update")
                    query.isExecutingQuery = false
                    return
                }
            }

            if isPaginated {
                let hasNextPage = hasMorePages(fetchedRowCount: result.rows.count, pageSize: query.rowsPerPage)
                let trimmedRows = hasNextPage ? Array(resultRows.prefix(query.rowsPerPage)) : resultRows
                query.hasNextPage = hasNextPage
                query.currentPage = requestedPage
                let trimmedResult = QueryResult.success(
                    rows: trimmedRows,
                    columnNames: result.columnNames,
                    executionTime: result.executionTime
                )
                query.finishQueryExecution(with: trimmedResult)

                query.cacheTableBrowsePage(
                    page: requestedPage,
                    rows: trimmedRows,
                    columnNames: result.columnNames,
                    hasNextPage: hasNextPage,
                    context: makePageCacheContext(
                        tableId: tableId,
                        databaseId: databaseId,
                        connectionId: connectionId
                    ),
                    maxCachedPages: Constants.tableBrowseMaxCachedPages
                )
            } else {
                query.hasNextPage = false
                query.currentPage = 0
                let compactedResult = QueryResult.success(
                    rows: resultRows,
                    columnNames: result.columnNames,
                    executionTime: result.executionTime
                )
                query.finishQueryExecution(with: compactedResult)
            }
            query.isResultsReadOnlyDueToContextMismatch = false

            query.cachedResultsTableId = table.id
            tabManager?.updateActiveTabResults(
                results: query.queryResults,
                columnNames: query.queryColumnNames
            )

            if metadataResolver.shouldFetch(for: table) {
                metadataResolver.startFetch(
                    for: table,
                    tableId: tableId,
                    databaseId: databaseId,
                    connectionId: connectionId
                )
            }
        } else {
            query.finishQueryExecution(with: result)
        }
    }

    // MARK: - Loading State

    private func startLoading(for table: TableInfo) {
        query.isExecutingTableQuery = true
        query.executingTableQueryTableId = table.id
    }

    private func finishLoadingIfCurrent(_ requestId: Int) {
        guard requestId == tableQueryRequestId else { return }
        query.isExecutingTableQuery = false
        query.executingTableQueryTableId = nil
    }

    // MARK: - Request Tracking

    private func isRequestCurrent(_ requestId: Int) -> Bool {
        requestId == tableQueryRequestId && !Task.isCancelled
    }

    private func hasInFlightLoadToSupersede() -> Bool {
        query.isExecutingTableQuery && (query.isExecutingQuery || query.currentQueryTask != nil)
    }

    // MARK: - Cache Helpers

    private func applyCachedPage(
        _ page: TableBrowsePageSnapshot,
        table: TableInfo,
        targetPage: Int
    ) {
        query.queryError = nil
        query.showTimeoutAlert = false
        query.queryExecutionTime = nil
        query.isExecutingQuery = false
        query.isExecutingTableQuery = false
        query.executingTableQueryTableId = nil
        query.hasNextPage = page.hasNextPage
        query.currentPage = targetPage
        query.updateQueryResults(page.rows, columnNames: page.columnNames)
        query.isResultsReadOnlyDueToContextMismatch = false
        query.cachedResultsTableId = table.id

        tabManager?.updateActiveTabResults(
            results: query.queryResults,
            columnNames: query.queryColumnNames
        )
    }

    private func makePageCacheContext(
        tableId: String,
        databaseId: String?,
        connectionId: UUID?
    ) -> TableBrowsePageCacheContext {
        TableBrowsePageCacheContext(
            connectionId: connectionId,
            databaseId: databaseId,
            tableId: tableId,
            rowsPerPage: query.rowsPerPage
        )
    }
}
