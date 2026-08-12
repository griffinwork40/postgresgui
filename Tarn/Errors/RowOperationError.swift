//
//  RowOperationError.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Errors that can occur during row operations (delete, update, etc.)
enum RowOperationError: Error {
    case noTableSelected
    case noRowsSelected
    case noPrimaryKey
    case metadataFetchFailed(String)
    case deleteFailed(String)
    case updateFailed(String)
}

// MARK: - LocalizedError Conformance

extension RowOperationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noTableSelected:
            return "No table selected"
        case .noRowsSelected:
            return "No rows selected"
        case .noPrimaryKey:
            return "This table has no primary key. This operation requires a primary key."
        case .metadataFetchFailed(let message):
            return "Failed to fetch table metadata: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete rows: \(message)"
        case .updateFailed(let message):
            return "Failed to update row: \(message)"
        }
    }
}
