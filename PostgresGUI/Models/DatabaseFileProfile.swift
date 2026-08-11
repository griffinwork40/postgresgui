//
//  DatabaseFileProfile.swift
//  PostgresGUI
//
//  SwiftData model representing a saved SQLite database file reference.
//  Replaces ConnectionProfile for file-based "connections."
//

import Foundation
import SwiftData

@Model
final class DatabaseFileProfile: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var filePath: String
    var bookmarkData: Data?
    var isFavorite: Bool
    var isReadOnly: Bool
    var lastOpenedAt: Date?
    var fileSize: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        filePath: String,
        bookmarkData: Data? = nil,
        isFavorite: Bool = false,
        isReadOnly: Bool = false,
        lastOpenedAt: Date? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        self.isFavorite = isFavorite
        self.isReadOnly = isReadOnly
        self.lastOpenedAt = lastOpenedAt
        self.fileSize = fileSize
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// The file name (last path component) for display.
    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// The display name: user-provided name if set, otherwise the file name.
    var displayName: String {
        name.isEmpty ? fileName : name
    }

    /// The file extension.
    var fileExtension: String {
        (filePath as NSString).pathExtension.lowercased()
    }
}
