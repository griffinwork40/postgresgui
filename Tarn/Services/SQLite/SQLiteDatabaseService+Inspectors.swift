//
//  SQLiteDatabaseService+Inspectors.swift
//  Tarn
//
//  SQLiteDatabaseService extension for schema visualization (Phase 6f).
//  Kept separate from the main file to stay under the 350-LOC ceiling.
//

import Foundation
import GRDB

extension SQLiteDatabaseService {

    // MARK: - Schema Visualization (Phase 6f)

    /// Fetch a schema overview: all tables with FK relationships.
    func fetchSchemaOverview() async throws -> SchemaOverview {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { db in
            try SchemaRelationshipService.fetchOverview(db: db)
        }
    }
}
