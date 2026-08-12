//
//  SchemaVisualizationViewModel.swift
//  Tarn
//
//  ViewModel for the Schema Visualization sheet.
//  Loads a SchemaOverview via SchemaRelationshipService and
//  drives navigation between tables.
//

import Foundation

// MARK: - SchemaVisualizationViewModel

@MainActor
@Observable
final class SchemaVisualizationViewModel {

    // MARK: - Load state

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(SchemaOverview)
        case failed(String)
    }

    // MARK: - Published state

    private(set) var loadState: LoadState = .idle
    var selectedTable: SchemaTable?

    // MARK: - Dependencies

    private let service: SQLiteDatabaseService

    init(service: SQLiteDatabaseService) {
        self.service = service
    }

    // MARK: - Load

    /// Fetch all tables and FK relationships, then publish the result.
    func refresh() async {
        loadState = .loading
        selectedTable = nil
        do {
            let overview = try await service.fetchSchemaOverview()
            loadState = .loaded(overview)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Derived convenience (safe to call from view)

    /// Outbound FKs for the selected table (empty when nothing selected / not loaded).
    var selectedOutbound: [SchemaRelationship] {
        guard case .loaded(let overview) = loadState,
              let table = selectedTable else { return [] }
        return overview.outbound(from: table)
    }

    /// Inbound FKs for the selected table (empty when nothing selected / not loaded).
    var selectedInbound: [SchemaRelationship] {
        guard case .loaded(let overview) = loadState,
              let table = selectedTable else { return [] }
        return overview.inbound(to: table)
    }

    /// `true` when data is available but contains no FK relationships.
    var hasNoRelationships: Bool {
        guard case .loaded(let overview) = loadState else { return false }
        return overview.relationships.isEmpty
    }
}


