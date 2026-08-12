//
//  DatabaseDiscoveryService.swift
//  Tarn
//
//  Recursively scans a directory for SQLite database files.
//  No GRDB dependency — uses raw byte inspection for magic-header detection.
//

import Foundation

// MARK: - DatabaseDiscoveryService

final class DatabaseDiscoveryService: Sendable {

    // MARK: - Constants

    private static let maxDepth = 5
    private static let maxFilesScanned = 10_000
    private static let maxFileSizeBytes: Int64 = 10 * 1_024 * 1_024 * 1_024 // 10 GB

    private static let knownExtensions: Set<String> = ["db", "sqlite", "sqlite3"]

    /// Directories to skip entirely during traversal.
    private static let skippedDirectoryNames: Set<String> = [
        "node_modules", ".git", "__pycache__", ".Trash"
    ]

    /// SQLite magic header: "SQLite format 3\0" (16 bytes).
    private static let sqliteMagic: [UInt8] = [
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    ]

    // MARK: - Public API

    /// Scan `directory` for SQLite databases.
    ///
    /// - Parameters:
    ///   - directory: Root URL to begin scanning.
    ///   - progress: Called on every file examined (count of files scanned so far).
    ///                Invoked on a background thread — callers must dispatch to main if needed.
    /// - Returns: All discovered databases, or throws if the task is cancelled.
    nonisolated func scan(
        directory: URL,
        progress: @Sendable @escaping (Int) -> Void
    ) async throws -> [DiscoveredDatabase] {
        try await Task.detached(priority: .userInitiated) {
            var results: [DiscoveredDatabase] = []
            var scanned = 0
            try Self.traverse(
                url: directory,
                depth: 0,
                scanned: &scanned,
                results: &results,
                progress: progress
            )
            return results
        }.value
    }

    // MARK: - Private Traversal

    private nonisolated static func traverse(
        url: URL,
        depth: Int,
        scanned: inout Int,
        results: inout [DiscoveredDatabase],
        progress: @Sendable (Int) -> Void
    ) throws {
        // Hard caps
        guard depth <= maxDepth else { return }
        guard scanned < maxFilesScanned else { return }

        try Task.checkCancellation()

        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .fileSizeKey, .contentModificationDateKey, .nameKey
        ]

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return }

        for case let childURL as URL in enumerator {
            guard scanned < maxFilesScanned else { break }
            try Task.checkCancellation()

            let rv = try? childURL.resourceValues(forKeys: Set(resourceKeys))

            // Skip symlinks
            if rv?.isSymbolicLink == true { continue }

            let name = rv?.name ?? childURL.lastPathComponent

            // Directory handling
            if rv?.isDirectory == true {
                // Skip .app bundles (packages)
                if rv?.isPackage == true { continue }
                // Skip known noisy directories
                if skippedDirectoryNames.contains(name) { continue }
                // Check path suffix for .app even if isPackage isn't set
                if childURL.pathExtension.lowercased() == "app" { continue }

                // Recurse only if within depth
                if depth + 1 <= maxDepth {
                    try traverse(
                        url: childURL,
                        depth: depth + 1,
                        scanned: &scanned,
                        results: &results,
                        progress: progress
                    )
                }
                continue
            }

            // File handling
            scanned += 1
            if scanned % 50 == 0 {
                progress(scanned)
            }

            let fileSize = Int64(rv?.fileSize ?? 0)
            guard fileSize <= maxFileSizeBytes else { continue }

            let ext = childURL.pathExtension.lowercased()
            let isKnownExtension = knownExtensions.contains(ext)

            if isKnownExtension || hasSQLiteMagicHeader(at: childURL) {
                let lastModified = rv?.contentModificationDate ?? Date()
                let walURL = childURL.deletingPathExtension()
                    .appendingPathExtension(childURL.pathExtension + "-wal")
                let hasWAL = fm.fileExists(atPath: walURL.path)

                results.append(DiscoveredDatabase(
                    fileName: name,
                    filePath: childURL,
                    fileSize: fileSize,
                    lastModified: lastModified,
                    hasWAL: hasWAL
                ))
            }
        }

        // Report final progress for this level
        progress(scanned)
    }

    // MARK: - Magic Header Detection

    private nonisolated static func hasSQLiteMagicHeader(at url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let data: Data
        if #available(macOS 10.15.4, *) {
            data = (try? fh.read(upToCount: 16)) ?? Data()
        } else {
            data = fh.readData(ofLength: 16)
        }
        guard data.count == 16 else { return false }
        return data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            return sqliteMagic.enumerated().allSatisfy { base[$0.offset] == $0.element }
        }
    }
}
