//
//  QueryResult.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Result of a query execution
struct QueryResult {
    let rows: [TableRow]
    let columnNames: [String]
    let executionTime: TimeInterval
    let error: Error?

    /// Success result
    static func success(
        rows: [TableRow],
        columnNames: [String],
        executionTime: TimeInterval
    ) -> QueryResult {
        QueryResult(
            rows: rows,
            columnNames: columnNames,
            executionTime: executionTime,
            error: nil
        )
    }

    /// Failure result
    static func failure(error: Error, executionTime: TimeInterval) -> QueryResult {
        QueryResult(
            rows: [],
            columnNames: [],
            executionTime: executionTime,
            error: error
        )
    }

    var isSuccess: Bool {
        error == nil
    }
}
