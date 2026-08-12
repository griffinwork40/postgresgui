//
//  AttachedDatabaseViewModel.swift
//  Tarn
//
//  Drives the Attached Databases panel — attach/detach lifecycle,
//  validation, per-database table listing, and error reporting.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - AttachedDatabaseViewModel

@MainActor
@Observable
final class AttachedDatabaseViewModel {

    // MARK: - State

    /// All databases currently reported by PRAGMA database_list ("main" is always first).
    private(set) var attachedDatabases: [AttachedDatabase] = []

    /// Tables keyed by alias — populated on demand when the user expands a database row.
    private(set) var tablesByAlias: [String: [TableInfo]] = [:]

    /// Non-fatal error surfaced to the UI (clears on next successful operation).
    private(set) var errorMessage: String?

    /// Set while any async database operation is in flight.
    private(set) var isBusy: Bool = false

    // MARK: - Dependencies

    private let service: SQLiteDatabaseService

    init(service: SQLiteDatabaseService) {
        self.service = service
    }

    // MARK: - Refresh

    /// Reload the database list from PRAGMA database_list.
    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            attachedDatabases = try await service.listAttachedDatabases()
            // Refresh table counts for already-expanded databases.
            for alias in tablesByAlias.keys {
                tablesByAlias[alias] = try await service.fetchTablesForAttached(alias: alias)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Attach

    /// Present a file picker, then attach the chosen database under `alias`.
    ///
    /// Validates the alias before opening the panel so the user sees errors immediately.
    /// Call with an empty alias to skip pre-validation (the panel won't open if alias is invalid).
    func attach(alias: String) async {
        do {
            try AttachedDatabaseService.validateAlias(alias)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let filePath = presentOpenPanel() else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try await service.attachDatabase(filePath: filePath, alias: alias)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Detach

    /// Detach the database identified by `alias`.
    func detach(alias: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.detachDatabase(alias: alias)
            tablesByAlias.removeValue(forKey: alias)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Table Loading

    /// Load (or reload) tables for a specific attached database alias.
    func loadTables(for alias: String) async {
        do {
            let tables = try await service.fetchTablesForAttached(alias: alias)
            tablesByAlias[alias] = tables
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Dismiss the current error message.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Validation Helpers

    /// Returns a user-facing description of why an alias is invalid, or nil if valid.
    func aliasValidationMessage(for alias: String) -> String? {
        guard !alias.isEmpty else { return nil }
        do {
            try AttachedDatabaseService.validateAlias(alias)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// True when the alias passes all validation rules.
    func isAliasValid(_ alias: String) -> Bool {
        (try? AttachedDatabaseService.validateAlias(alias)) != nil
    }

    // MARK: - Private Helpers

    private func presentOpenPanel() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select Database to Attach"
        panel.message = "Choose a SQLite database file to attach."
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sqlite") ?? .data,
            UTType(filenameExtension: "db")     ?? .data,
            UTType(filenameExtension: "sqlite3") ?? .data
        ]
        panel.canChooseFiles        = true
        panel.canChooseDirectories  = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
