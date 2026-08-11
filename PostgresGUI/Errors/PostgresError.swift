//
//  PostgresError.swift
//  PostgresGUI
//
//  Generic error mapping and message extraction utilities.
//

import Foundation

/// Utility for mapping and extracting user-friendly error messages from app error types
enum PostgresError {

    /// Map an error to a known app error type where possible
    /// - Parameter error: The error to map
    /// - Returns: Mapped ConnectionError, DatabaseError, or the original error if unmappable
    nonisolated static func mapError(_ error: Error) -> Error {
        // Already a known app error type — return as-is
        if error is ConnectionError || error is DatabaseError {
            return error
        }

        // Wrap unknown errors in ConnectionError.unknownError
        return ConnectionError.unknownError(error)
    }

    /// Extract detailed message from any error for display in alerts
    nonisolated static func extractDetailedMessage(_ error: Error) -> String {
        if let databaseError = error as? DatabaseError {
            return databaseError.errorDescription ?? "Query failed"
        }

        if let connectionError = error as? ConnectionError {
            if case .unknownError(let underlying) = connectionError {
                return cleanErrorDescription(String(describing: underlying))
            }
            return connectionError.errorDescription ?? "Connection failed"
        }

        return cleanErrorDescription(String(describing: error))
    }

    /// Clean up raw error descriptions into user-friendly messages
    private nonisolated static func cleanErrorDescription(_ description: String) -> String {
        let lower = description.lowercased()

        if lower.contains("connection refused") || lower.contains("(61)") {
            return "Connection refused"
        }
        if lower.contains("no such host") || lower.contains("nodename nor servname") {
            return "Could not resolve host"
        }
        if lower.contains("timeout") || lower.contains("timed out") || lower.contains("(60)") {
            return "Connection timed out"
        }
        if lower.contains("network is unreachable") {
            return "Network unreachable"
        }
        if lower.contains("ssl") || lower.contains("tls") {
            return "SSL/TLS connection failed"
        }

        return description.isEmpty ? "An unknown error occurred" : description
    }
}
