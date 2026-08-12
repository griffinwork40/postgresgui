//
//  Timeout.swift
//  Tarn
//
//  Utility for adding timeouts to async operations
//

import Foundation

/// Executes an async operation with a timeout.
/// - Parameters:
///   - seconds: Maximum time to wait for the operation
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: `DatabaseError.timeout` if the operation exceeds the timeout, or any error from the operation
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }

        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: seconds.nanoseconds)
            throw DatabaseError.timeout
        }

        // Return the first result (either success or timeout)
        let result = try await group.next()!

        // Cancel the other task
        group.cancelAll()

        return result
    }
}

/// Executes an async operation with the default database operation timeout.
/// - Parameter operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: `DatabaseError.timeout` if the operation exceeds the timeout, or any error from the operation
func withDatabaseTimeout<T: Sendable>(
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTimeout(seconds: Constants.Timeout.databaseOperation, operation: operation)
}
