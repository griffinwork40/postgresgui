//
//  SQLiteLockHandler.swift
//  PostgresGUI
//
//  Maps SQLite lock/busy error codes to user-friendly messages
//  and provides retry logic with a configurable timeout.
//

import Foundation
import GRDB

// MARK: - Lock Error

/// User-presentable description of a SQLite locking condition.
struct SQLiteLockError: LocalizedError {
    let code: ResultCode
    let underlyingMessage: String?

    var errorDescription: String? { userFacingTitle }
    var recoverySuggestion: String? { retrySuggestion }

    var userFacingTitle: String {
        switch code {
        case .SQLITE_BUSY:
            return "Database is busy"
        case .SQLITE_LOCKED:
            return "Database table is locked"
        default:
            return "Database access error"
        }
    }

    var userFacingBody: String {
        switch code {
        case .SQLITE_BUSY:
            return "Another application may be using this database. Close any other apps that have the file open, then retry."
        case .SQLITE_LOCKED:
            return "A database table is locked by another operation. Try again in a moment."
        default:
            return underlyingMessage ?? "An unexpected database error occurred."
        }
    }

    private var retrySuggestion: String {
        "Retry the operation once the lock is released."
    }

    var isRetryable: Bool {
        code == .SQLITE_BUSY || code == .SQLITE_LOCKED
    }
}

// MARK: - Lock Handler

struct SQLiteLockHandler {

    // MARK: - Constants

    static let defaultMaxRetries: Int = 3
    static let defaultRetryDelaySeconds: Double = 0.5

    // MARK: - Error Classification

    /// Returns a SQLiteLockError if the given error is a lock/busy error; nil otherwise.
    static func lockError(from error: Error) -> SQLiteLockError? {
        guard let dbError = error as? GRDB.DatabaseError else { return nil }
        switch dbError.resultCode {
        case .SQLITE_BUSY:
            return SQLiteLockError(code: .SQLITE_BUSY, underlyingMessage: dbError.message)
        case .SQLITE_LOCKED:
            return SQLiteLockError(code: .SQLITE_LOCKED, underlyingMessage: dbError.message)
        default:
            return nil
        }
    }

    /// Returns a user-friendly message if the error is a lock/busy condition.
    static func userFacingMessage(for error: Error) -> String? {
        lockError(from: error)?.userFacingBody
    }

    /// Returns true if the error indicates a retryable lock condition.
    static func isRetryable(_ error: Error) -> Bool {
        lockError(from: error)?.isRetryable ?? false
    }

    // MARK: - Retry Logic

    /// Execute an async throwing operation, retrying on SQLITE_BUSY / SQLITE_LOCKED.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts after the initial failure.
    ///   - delaySeconds: Seconds to wait between attempts.
    ///   - operation: The operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The last error if all retries are exhausted.
    static func withRetry<T>(
        maxRetries: Int = defaultMaxRetries,
        delaySeconds: Double = defaultRetryDelaySeconds,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch let error where isRetryable(error) {
                lastError = error
                if attempt < maxRetries {
                    let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            } catch {
                // Non-retryable error — propagate immediately
                throw error
            }
        }

        throw lastError ?? NSError(domain: "SQLiteLockHandler", code: -1)
    }

    // MARK: - Retry Result (non-throwing variant)

    enum RetryResult<T> {
        case success(T)
        case failure(SQLiteLockError)
        case otherError(Error)
    }

    /// Non-throwing variant that wraps the result into a RetryResult.
    static func tryWithRetry<T>(
        maxRetries: Int = defaultMaxRetries,
        delaySeconds: Double = defaultRetryDelaySeconds,
        operation: () async throws -> T
    ) async -> RetryResult<T> {
        do {
            let value = try await withRetry(
                maxRetries: maxRetries,
                delaySeconds: delaySeconds,
                operation: operation
            )
            return .success(value)
        } catch let error where lockError(from: error) != nil {
            return .failure(lockError(from: error)!)
        } catch {
            return .otherError(error)
        }
    }
}
