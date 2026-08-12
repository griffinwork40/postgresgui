//
//  SQLiteDropTarget.swift
//  Tarn
//
//  Drag-and-drop support for opening SQLite files by dropping them
//  onto the main window. Validates extension and magic bytes before connecting.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Magic Bytes Validation

private enum SQLiteMagic {
    /// SQLite databases begin with this 16-byte header string.
    static let header = Data("SQLite format 3\0".utf8)

    static func isSQLiteFile(at url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let bytes = fh.readData(ofLength: 16)
        return bytes == header
    }
}

// MARK: - Drop Delegate

/// Validation and connection logic for SQLite file drops.
/// Separates drag-drop plumbing from the confirmation UI.
struct SQLiteDropHandler {

    static let validExtensions: Set<String> = ["db", "sqlite", "sqlite3", "db3", "s3db"]

    /// Accepted UTTypes for the `onDrop` modifier.
    static var acceptedTypes: [UTType] {
        // .fileURL covers all file drops; we filter by extension ourselves.
        [.fileURL]
    }

    /// Validate and return the first acceptable SQLite URL from a drop.
    /// Returns nil if no valid SQLite file is found.
    static func resolve(providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }

            guard let url = await loadFileURL(from: provider) else { continue }

            let ext = url.pathExtension.lowercased()
            guard validExtensions.contains(ext) else { continue }

            // Check magic bytes to confirm it's actually a SQLite file
            guard SQLiteMagic.isSQLiteFile(at: url) else { continue }

            return url
        }
        return nil
    }

    // MARK: - Private

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Drop Target View Modifier

/// Attaches a SQLite drag-and-drop target to any view.
///
/// Usage:
/// ```swift
/// MainSplitView()
///     .sqliteDropTarget { url in
///         Task { await openFile(at: url) }
///     }
/// ```
struct SQLiteDropTargetModifier: ViewModifier {
    let onDrop: (URL) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    DropHighlightOverlay()
                }
            }
            .onDrop(of: SQLiteDropHandler.acceptedTypes, isTargeted: $isTargeted) { providers in
                Task {
                    if let url = await SQLiteDropHandler.resolve(providers: providers) {
                        await MainActor.run { onDrop(url) }
                    }
                }
                return true
            }
    }
}

extension View {
    /// Drop a SQLite file onto this view to open it.
    /// The `onDrop` closure is called on the main actor with the validated file URL.
    func sqliteDropTarget(onDrop: @escaping (URL) -> Void) -> some View {
        modifier(SQLiteDropTargetModifier(onDrop: onDrop))
    }
}

// MARK: - Drop Highlight Overlay

private struct DropHighlightOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, dash: [8])
                )
                .padding(8)

            VStack(spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)

                Text("Drop SQLite file to open")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .allowsHitTesting(false)
    }
}
