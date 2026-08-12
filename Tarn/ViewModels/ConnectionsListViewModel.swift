//
//  ConnectionsListViewModel.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftData

/// ViewModel for ConnectionsListView
@Observable
@MainActor
class ConnectionsListViewModel {
    private let appState: AppState
    private let connectionService: ConnectionServiceProtocol
    private let keychainService: KeychainServiceProtocol

    // UI State
    var connectionToDelete: ConnectionProfile?
    var showDeleteConfirmation = false
    var deleteError: String?
    var connectionError: String?
    var showConnectionError = false

    init(
        appState: AppState,
        connectionService: ConnectionServiceProtocol,
        keychainService: KeychainServiceProtocol
    ) {
        self.appState = appState
        self.connectionService = connectionService
        self.keychainService = keychainService
    }

    /// Connect to a database
    func connect(to connection: ConnectionProfile, modelContext: ModelContext) async {
        let result = await connectionService.connect(to: connection, password: nil, saveAsLast: true)

        switch result {
        case .success:
            try? modelContext.save()
        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            DebugLog.print("Failed to connect - detailed error: \(String(reflecting: error))")

            // Show user-friendly error message
            if let connectionError = error as? ConnectionError {
                var errorMessage = connectionError.errorDescription ?? "Connection failed."
                if let recovery = connectionError.recoverySuggestion {
                    errorMessage += "\n\n\(recovery)"
                }
                self.connectionError = errorMessage
            } else {
                self.connectionError = error.localizedDescription
            }
            showConnectionError = true
        }
    }

    /// Delete a connection
    func deleteConnection(
        _ connection: ConnectionProfile,
        connections: [ConnectionProfile],
        modelContext: ModelContext
    ) async {
        DebugLog.print("🗑️  [ConnectionsListViewModel] Deleting connection: \(connection.displayName)")

        do {
            // Check if this is the currently active connection
            let isActiveConnection = appState.connection.currentConnection?.id == connection.id

            // Check if this is the last connection before deletion
            let wasLastConnection = connections.count == 1

            // Delete password from Keychain
            try keychainService.deletePassword(for: connection.id)

            // Disconnect if this is the active connection
            if isActiveConnection {
                await connectionService.disconnect()

                // Clear last connection ID if this was the last connection
                if let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
                   lastConnectionIdString == connection.id.uuidString {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
                }
            }

            // Delete from SwiftData
            modelContext.delete(connection)
            try modelContext.save()

            DebugLog.print("✅ [ConnectionsListViewModel] Connection deleted successfully")
            connectionToDelete = nil

            // If this was the last connection, clear last connection ID
            // (Welcome screen will show automatically when connections.isEmpty)
            if wasLastConnection {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            }

        } catch {
            DebugLog.print("❌ [ConnectionsListViewModel] Error deleting connection: \(error)")
            if let keychainError = error as? KeychainError {
                deleteError = keychainError.errorDescription ?? "Failed to delete connection."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
}
