//
//  DatabaseDiscoveryView.swift
//  PostgresGUI
//
//  Sheet for discovering SQLite databases by recursively scanning a directory.
//

import SwiftUI
import AppKit

struct DatabaseDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when the user selects a database and taps Open.
    let onOpen: (URL) -> Void

    @State private var viewModel = DatabaseDiscoveryViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top controls
                controlsHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()

                // Results area
                if viewModel.isScanning && viewModel.discoveredDatabases.isEmpty {
                    scanningPlaceholder
                } else if !viewModel.isScanning && viewModel.discoveredDatabases.isEmpty {
                    emptyState
                } else {
                    resultsTable
                }

                Spacer(minLength: 0)

                // Error banner
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }
            }
            .frame(minWidth: 640, minHeight: 420)
            .navigationTitle("Discover Databases")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { commitOpen() }
                        .disabled(viewModel.selectedDatabase == nil || viewModel.isScanning)
                }
            }
        }
    }

    // MARK: - Controls Header

    private var controlsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Scan a folder for SQLite databases")
                    .font(.system(size: 13, weight: .medium))
                Text("Searches up to 5 levels deep. Skips bundles, node_modules, and .git.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("\(viewModel.filesScanned) files scanned")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Cancel") { viewModel.cancelScan() }
                        .controlSize(.small)
                }
            } else {
                Button(action: chooseDirectory) {
                    Label("Choose Directory…", systemImage: "folder")
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Scanning Placeholder

    private var scanningPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Scanning for SQLite databases…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("\(viewModel.filesScanned) files examined")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No SQLite databases found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Choose a directory to scan, or try a different folder.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Results Table

    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(viewModel.discoveredDatabases.count) database\(viewModel.discoveredDatabases.count == 1 ? "" : "s") found")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

            List(viewModel.discoveredDatabases, selection: $viewModel.selectedDatabase) { db in
                DiscoveredDatabaseRow(db: db)
                    .tag(db)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
            }
            .listStyle(.plain)
            .onTapGesture(count: 2) {
                if viewModel.selectedDatabase != nil { commitOpen() }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { viewModel.errorMessage = nil }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary)
    }

    // MARK: - Actions

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Directory to Scan"
        panel.message = "SQLiteGUI will search this folder for SQLite databases"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.startScan(directory: url)
    }

    private func commitOpen() {
        guard let db = viewModel.selectedDatabase else { return }
        dismiss()
        onOpen(db.filePath)
    }
}

// MARK: - DiscoveredDatabaseRow

private struct DiscoveredDatabaseRow: View {
    let db: DiscoveredDatabase

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(db.fileName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if db.hasWAL {
                        Badge(text: "WAL", color: .orange)
                    }
                }
                Text(db.filePath.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(db.formattedFileSize)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(Self.dateFormatter.string(from: db.lastModified))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
