//
//  TableBrowsePageCache.swift
//  Tarn
//
//  Extracted from QueryState.swift — table-browse page cache structs and methods.
//

import Foundation

/// Cache key for table-browse pagination pages.
/// Keeps cache scoped to current connection/database/table/page-size context.
struct TableBrowsePageCacheContext: Equatable {
    let connectionId: UUID?
    let databaseId: String?
    let tableId: String
    let rowsPerPage: Int
}

/// Snapshot for a cached table-browse page.
struct TableBrowsePageSnapshot {
    let rows: [TableRow]
    let columnNames: [String]
    let hasNextPage: Bool
}

// MARK: - Table Browse Page Cache (In-Memory)

extension QueryState {

    // In-memory table-browse page cache (current context only)
    // NOTE: Stored properties cannot live in extensions on classes; these remain
    // in the main QueryState body. The methods below operate on those properties.

    /// Get a cached page for the given table-browse context.
    /// Resets cache if context changed.
    func cachedTableBrowsePage(
        for page: Int,
        context: TableBrowsePageCacheContext
    ) -> TableBrowsePageSnapshot? {
        guard page >= 0 else { return nil }
        ensureTableBrowsePageCacheContext(context)
        guard let snapshot = tableBrowsePageCache[page] else {
            return nil
        }
        touchTableBrowsePageInLRU(page)
        return snapshot
    }

    /// Store a page in table-browse cache and evict least-recently-used pages
    /// to keep memory bounded.
    func cacheTableBrowsePage(
        page: Int,
        rows: [TableRow],
        columnNames: [String],
        hasNextPage: Bool,
        context: TableBrowsePageCacheContext,
        maxCachedPages: Int = Constants.tableBrowseMaxCachedPages
    ) {
        guard page >= 0 else { return }
        ensureTableBrowsePageCacheContext(context)

        tableBrowsePageCache[page] = TableBrowsePageSnapshot(
            rows: rows,
            columnNames: columnNames,
            hasNextPage: hasNextPage
        )
        touchTableBrowsePageInLRU(page)

        guard maxCachedPages > 0 else {
            clearTableBrowsePageCache()
            return
        }

        while tableBrowsePageCache.count > maxCachedPages {
            guard let leastRecentPage = tableBrowsePageCacheLRU.first else { break }
            tableBrowsePageCache.removeValue(forKey: leastRecentPage)
            tableBrowsePageCacheLRU.removeFirst()
        }
    }

    /// Clear table-browse page cache.
    func clearTableBrowsePageCache() {
        tableBrowsePageCacheContext = nil
        tableBrowsePageCache.removeAll()
        tableBrowsePageCacheLRU.removeAll()
    }

    /// Number of pages currently cached for table-browse (test/debug helper).
    var tableBrowsePageCacheCount: Int {
        tableBrowsePageCache.count
    }

    func ensureTableBrowsePageCacheContext(_ context: TableBrowsePageCacheContext) {
        guard tableBrowsePageCacheContext != context else { return }
        tableBrowsePageCacheContext = context
        tableBrowsePageCache.removeAll()
        tableBrowsePageCacheLRU.removeAll()
    }

    func touchTableBrowsePageInLRU(_ page: Int) {
        if let existingIndex = tableBrowsePageCacheLRU.firstIndex(of: page) {
            tableBrowsePageCacheLRU.remove(at: existingIndex)
        }
        tableBrowsePageCacheLRU.append(page)
    }
}
