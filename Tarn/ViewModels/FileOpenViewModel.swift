//
//  FileOpenViewModel.swift
//  Tarn
//
//  ViewModel for FileOpenView — handles NSOpenPanel invocation and
//  SwiftData persistence of DatabaseFileProfile records.
//

import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// ViewModel for the SQLite file-open sheet.
@Observable
@MainActor
class FileOpenViewModel {

    // MARK: - State

    var isReadOnly: Bool = false

    // MARK: - File Panel

    /// Present an NSOpenPanel and return the selected file path, or nil if cancelled.
    func openFilePanel() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Open SQLite Database"
        panel.message = "Select a SQLite database file"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sqlite") ?? .data,
            UTType(filenameExtension: "db") ?? .data,
            UTType(filenameExtension: "sqlite3") ?? .data
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url.path
    }

    // MARK: - Profile Persistence

    /// Fetch an existing `DatabaseFileProfile` matching `filePath`, or create a new one.
    /// Updates `lastOpenedAt` and `isReadOnly` and saves the context.
    func createOrUpdateProfile(
        filePath: String,
        modelContext: ModelContext
    ) -> DatabaseFileProfile {
        // Look for an existing profile with this path
        let descriptor = FetchDescriptor<DatabaseFileProfile>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        let existing = try? modelContext.fetch(descriptor)
        let profile: DatabaseFileProfile

        if let found = existing?.first {
            profile = found
        } else {
            let fileName = (filePath as NSString).lastPathComponent
            let name = (fileName as NSString).deletingPathExtension
            profile = DatabaseFileProfile(name: name, filePath: filePath)
            modelContext.insert(profile)
        }

        profile.lastOpenedAt = Date()
        profile.isReadOnly = isReadOnly
        profile.updatedAt = Date()

        try? modelContext.save()
        return profile
    }
}
