//
//  ConnectionService.swift
//  PostgresGUI
//
//  Service for managing SQLite database file connections.
//

import Foundation
import SwiftData

/// Service for managing database connections
@MainActor
class ConnectionService: ConnectionServiceProtocol {
    private let appState: AppState
    private let keychainService: KeychainServiceProtocol
    private let userDefaults: UserDefaultsProtocol

    init(
        appState: AppState,
        keychainService: KeychainServiceProtocol,
        userDefaults: UserDefaultsProtocol? = nil
    ) {
        self.appState = appState
        self.keychainService = keychainService
        self.userDefaults = userDefaults ?? UserDefaultsWrapper()
    }

    /// Connect to a PostgreSQL connection profile.
    /// Not supported in the SQLite-only build — always returns a failure.
    func connect(
        to connection: ConnectionProfile,
        password: String? = nil,
        saveAsLast: Bool = true
    ) async -> ConnectionResult {
        return .failure(FileOpenError.notSupported)
    }

    /// Disconnect from the current database
    func disconnect() async {
        DebugLog.print("🔌 [ConnectionService] Disconnecting")
        await appState.connection.databaseService.disconnect()

        appState.connection.currentConnection = nil
        appState.connection.databases = []
        appState.connection.databasesVersion += 1
        appState.connection.tables = []
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
    }

    /// Delete a connection profile and its associated keychain entries
    func delete(connection: ConnectionProfile, from modelContext: ModelContext) async {
        DebugLog.print("🗑️ [ConnectionService] Deleting connection: \(connection.displayName)")

        try? keychainService.deletePassword(for: connection.id)

        // If deleting the active connection, clear state
        if appState.connection.currentConnection?.id == connection.id {
            appState.connection.currentConnection = nil
            appState.connection.selectedDatabase = nil
            appState.connection.tables = []
            appState.connection.selectedTable = nil
            appState.connection.databases = []
            appState.connection.databasesVersion += 1
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
        }

        modelContext.delete(connection)
        try? modelContext.save()

        DebugLog.print("✅ [ConnectionService] Connection deleted")
    }

    // MARK: - SQLite File Connection

    /// Connect to a SQLite database file.
    func connectFile(to profile: DatabaseFileProfile) async -> ConnectionResult {
        do {
            DebugLog.print("📂 [ConnectionService] Opening SQLite file: \(profile.filePath)")
            let sqliteService = SQLiteDatabaseService()
            try await sqliteService.connect(filePath: profile.filePath, readOnly: profile.isReadOnly)
            appState.connection.databaseService = sqliteService
            appState.connection.activeConnection = .sqlite(profile)
            DebugLog.print("✅ [ConnectionService] SQLite file opened: \(profile.displayName)")
            return .success
        } catch {
            DebugLog.print("❌ [ConnectionService] SQLite file open failed: \(error)")
            return .failure(error)
        }
    }
}
