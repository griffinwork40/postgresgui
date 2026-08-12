//
//  ConnectionError.swift
//  Tarn
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum ConnectionError: LocalizedError, Equatable {
    case invalidHost(String)
    case invalidPort
    case authenticationFailed
    case databaseNotFound(String)
    case timeout
    case networkUnreachable
    case notConnected
    case connectionCancelled
    case sslContextCreationFailed(String)
    case unknownError(Error)
    case invalidConnectionString(ConnectionStringParser.ParseError)
    case unsupportedParameters([String])
    
    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Invalid host: \(host)"
        case .invalidPort:
            return "Invalid port number"
        case .authenticationFailed:
            return "Authentication failed. Please check your username and password."
        case .databaseNotFound(let database):
            return "Database '\(database)' not found."
        case .timeout:
            return "Connection timeout. Please check your network connection."
        case .networkUnreachable:
            return "Network unreachable. Please check your connection settings."
        case .notConnected:
            return "Not connected to database."
        case .connectionCancelled:
            return "Connection was superseded by a newer request."
        case .sslContextCreationFailed(let message):
            return "Failed to initialize SSL/TLS context: \(message). Secure connection cannot be established."
        case .unknownError(let error):
            // Try to get detailed error information
            let nsError = error as NSError
            var errorMessage = error.localizedDescription
            
            // If we have an NSError, try to extract more details
            if nsError.domain != "" {
                // Check for underlying error details
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                    errorMessage = underlyingError.localizedDescription
                } else if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                    errorMessage = failureReason
                } else if !nsError.localizedDescription.isEmpty && nsError.localizedDescription != errorMessage {
                    errorMessage = nsError.localizedDescription
                }
                
                // Include domain and code for debugging
                if nsError.domain != "NSCocoaErrorDomain" {
                    errorMessage += " (\(nsError.domain), code: \(nsError.code))"
                }
            }
            
            return "Connection failed: \(errorMessage)"
        case .invalidConnectionString(let parseError):
            return parseError.errorDescription
        case .unsupportedParameters(let params):
            return "Connection string contains unsupported parameters: \(params.joined(separator: ", "))"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidHost:
            return "Please enter a valid hostname or IP address."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .authenticationFailed:
            return "Verify your username and password are correct. For localhost, try passwordless authentication first."
        case .databaseNotFound:
            return "Make sure the database exists and you have permission to access it."
        case .timeout:
            return "Check that PostgreSQL is running and the host/port are correct."
        case .networkUnreachable:
            return "Verify your network connection and firewall settings."
        case .notConnected:
            return "Please connect to a database first."
        case .connectionCancelled:
            return nil
        case .sslContextCreationFailed:
            return "Check that your SSL certificates are valid and properly configured. If you want to connect without SSL, select 'Disable' or 'Prefer' mode."
        case .unknownError:
            return "Please try again or check the server logs for more details."
        case .invalidConnectionString(let parseError):
            return parseError.recoverySuggestion
        case .unsupportedParameters:
            return "These parameters will be ignored. The connection will proceed with basic settings."
        }
    }
    
    // MARK: - Equatable Conformance
    
    static func == (lhs: ConnectionError, rhs: ConnectionError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidHost(let lhsHost), .invalidHost(let rhsHost)):
            return lhsHost == rhsHost
        case (.invalidPort, .invalidPort):
            return true
        case (.authenticationFailed, .authenticationFailed):
            return true
        case (.databaseNotFound(let lhsDb), .databaseNotFound(let rhsDb)):
            return lhsDb == rhsDb
        case (.timeout, .timeout):
            return true
        case (.networkUnreachable, .networkUnreachable):
            return true
        case (.notConnected, .notConnected):
            return true
        case (.connectionCancelled, .connectionCancelled):
            return true
        case (.sslContextCreationFailed(let lhs), .sslContextCreationFailed(let rhs)):
            return lhs == rhs
        case (.unknownError, .unknownError):
            // For unknownError, we can't easily compare the underlying errors
            // In tests, we should use specific error types instead
            return false
        case (.invalidConnectionString(let lhsError), .invalidConnectionString(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.unsupportedParameters(let lhsParams), .unsupportedParameters(let rhsParams)):
            return lhsParams == rhsParams
        default:
            return false
        }
    }
}
