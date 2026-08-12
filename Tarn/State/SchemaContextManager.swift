//
//  SchemaContextManager.swift
//  Tarn
//
//  Extracted from AppState.swift — owns the SET search_path
//  debounce and execution for Postgres connections.
//  No-ops for SQLite (which has no search_path concept).
//

import Foundation

@MainActor
final class SchemaContextManager {
    // MARK: - Dependencies

    private let connection: ConnectionState

    // MARK: - Task State

    private var searchPathTask: Task<Void, Never>?

    // MARK: - Init

    init(connection: ConnectionState) {
        self.connection = connection
    }

    // MARK: - Public API

    /// Set the search_path with debounce to prevent race conditions during rapid tab switching.
    func setSchemaSearchPathDebounced(_ schema: String?) {
        searchPathTask?.cancel()
        searchPathTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await setSchemaSearchPath(schema)
        }
    }

    /// Set the search_path for query context when a schema is selected.
    /// Use `setSchemaSearchPathDebounced` for tab switches and user-initiated schema changes.
    func setSchemaSearchPath(_ schema: String?) async {
        // SQLite has no search_path concept — skip for file-based connections
        if case .sqlite = connection.activeConnection { return }
        guard connection.isConnected else { return }

        let searchPath: String
        if let schema = schema {
            searchPath = schema == "public" ? "public" : "\"\(schema)\", public"
        } else {
            searchPath = "public"
        }

        let sql = "SET search_path TO \(searchPath)"
        DebugLog.print("🔧 Setting schema: \(schema ?? "nil") → SQL: \(sql)")

        do {
            _ = try await connection.databaseService.executeQuery(sql)
            connection.schemaError = nil
        } catch {
            DebugLog.print("❌ Failed to set search_path: \(error)")
            connection.schemaError = "Failed to set schema context: \(error.localizedDescription)"
        }
    }

    /// Cancel any pending search_path task.
    func cancel() {
        searchPathTask?.cancel()
    }
}
