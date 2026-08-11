//
//  FileOpenError.swift
//  PostgresGUI
//
//  Error types for SQLite file-based database access.
//

import Foundation

enum FileOpenError: LocalizedError, Equatable {
    case fileNotFound(String)
    case permissionDenied(String)
    case notADatabase(String)
    case fileLocked(String)
    case notConnected
    case unknownError(String)
    case notSupported

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .notADatabase(let path):
            return "Not a valid SQLite database: \(path)"
        case .fileLocked(let path):
            return "Database file is locked: \(path)"
        case .notConnected:
            return "No database is currently open."
        case .unknownError(let message):
            return message
        case .notSupported:
            return "Operation not supported for file-based databases."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Check that the file exists and the path is correct."
        case .permissionDenied:
            return "Check file permissions or try opening with read-only access."
        case .notADatabase:
            return "The file may be corrupted or is not a SQLite database."
        case .fileLocked:
            return "Another application may be using the database. Try again in a moment."
        case .notConnected:
            return "Open a database file first."
        case .unknownError:
            return nil
        case .notSupported:
            return "Use a PostgreSQL connection for this feature."
        }
    }
}
