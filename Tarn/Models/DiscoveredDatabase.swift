//
//  DiscoveredDatabase.swift
//  Tarn
//
//  Represents a SQLite database found during directory scanning.
//

import Foundation

struct DiscoveredDatabase: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let filePath: URL
    let fileSize: Int64
    let lastModified: Date
    let hasWAL: Bool

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: URL,
        fileSize: Int64,
        lastModified: Date,
        hasWAL: Bool
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileSize = fileSize
        self.lastModified = lastModified
        self.hasWAL = hasWAL
    }

    /// Human-readable file size string.
    var formattedFileSize: String {
        let bytes = Double(fileSize)
        if fileSize < 1_024 {
            return "\(fileSize) B"
        } else if fileSize < 1_024 * 1_024 {
            return String(format: "%.1f KB", bytes / 1_024)
        } else if fileSize < 1_024 * 1_024 * 1_024 {
            return String(format: "%.1f MB", bytes / (1_024 * 1_024))
        } else {
            return String(format: "%.2f GB", bytes / (1_024 * 1_024 * 1_024))
        }
    }
}
