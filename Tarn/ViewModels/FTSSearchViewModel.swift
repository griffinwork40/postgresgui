//
//  FTSSearchViewModel.swift
//  Tarn
//
//  ViewModel for the FTS Search panel.
//  Loads available FTS tables, drives MATCH queries, and surfaces results.
//

import Foundation
import SwiftUI

// MARK: - FTSSearchViewModel

@MainActor
@Observable
final class FTSSearchViewModel {

    // MARK: - Load State

    enum LoadState {
        case idle
        case loading
        case loaded([FTSTableInfo])
        case failed(String)
    }

    // MARK: - Search State

    enum SearchState {
        case idle
        case searching
        case results(QueryResult)
        case failed(String)
    }

    // MARK: - Published State

    private(set) var loadState: LoadState = .idle
    private(set) var searchState: SearchState = .idle

    /// The table the user has selected in the picker.
    var selectedTable: FTSTableInfo?

    /// The search term bound to the TextField.
    var searchQuery: String = ""

    // MARK: - Convenience Accessors

    var ftsTables: [FTSTableInfo] {
        if case .loaded(let tables) = loadState { return tables }
        return []
    }

    var results: QueryResult? {
        if case .results(let r) = searchState { return r }
        return nil
    }

    var isSearching: Bool {
        if case .searching = searchState { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    // MARK: - Dependencies

    private let service: SQLiteDatabaseService

    init(service: SQLiteDatabaseService) {
        self.service = service
    }

    // MARK: - Load FTS Tables

    /// Discover all FTS virtual tables in the connected database.
    func loadFTSTables() async {
        loadState = .loading
        do {
            let tables = try await service.fetchFTSTables()
            loadState = .loaded(tables)
            // Auto-select the first table if none selected yet
            if selectedTable == nil {
                selectedTable = tables.first
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Search

    /// Execute a MATCH search against the selected FTS table.
    func search() async {
        guard let table = selectedTable else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        searchState = .searching
        do {
            let result = try await service.searchFTS(table: table, query: query)
            if let error = result.error {
                searchState = .failed(error.localizedDescription)
            } else {
                searchState = .results(result)
            }
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }

    /// Clear results and reset the search field.
    func clearSearch() {
        searchQuery = ""
        searchState = .idle
    }

    // MARK: - Helpers

    /// Human-readable row count for the current results.
    var resultCountLabel: String {
        guard let r = results else { return "" }
        let n = r.rows.count
        return n == 1 ? "1 row" : "\(n) rows"
    }

    /// Whether the search button should be enabled.
    var canSearch: Bool {
        selectedTable != nil && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
