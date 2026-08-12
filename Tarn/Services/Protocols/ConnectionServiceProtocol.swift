//
//  ConnectionServiceProtocol.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftData

/// Result of connection operation
enum ConnectionResult {
    case success
    case failure(Error)
}

/// Protocol for connection management operations
@MainActor
protocol ConnectionServiceProtocol {
    /// Connect to a database using a connection profile
    /// - Parameters:
    ///   - connection: The connection profile to use
    ///   - password: Optional password (if not provided, will fetch from keychain)
    ///   - saveAsLast: Whether to save this as the last connected profile (default: true)
    /// - Returns: ConnectionResult indicating success or failure
    func connect(
        to connection: ConnectionProfile,
        password: String?,
        saveAsLast: Bool
    ) async -> ConnectionResult

    /// Disconnect from the current database
    func disconnect() async

    /// Delete a connection profile and its associated keychain password
    /// - Parameter connection: The connection profile to delete
    /// - Parameter modelContext: The SwiftData model context to delete from
    func delete(connection: ConnectionProfile, from modelContext: ModelContext) async
}
