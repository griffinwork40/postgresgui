//
//  FileOpenView.swift
//  PostgresGUI
//
//  Sheet for opening a SQLite database file. Presents an NSOpenPanel and shows
//  recently opened files. The `onOpen` closure is called with the persisted
//  DatabaseFileProfile so the caller (RootView / RootViewModel) can connect.
//

import SwiftUI
import SwiftData

struct FileOpenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Called when the user taps Open with a valid file. The caller connects to the file.
    let onOpen: (DatabaseFileProfile) -> Void

    @State private var viewModel = FileOpenViewModel()
    @State private var pendingFilePath: String?

    // Fetch all profiles unsorted; sort in-body on the optional lastOpenedAt so we
    // get "most recently opened first" semantics without relying on SwiftData's
    // inconsistent handling of optional keypath sorts.
    @Query private var recentProfiles: [DatabaseFileProfile]

    private var sortedRecentProfiles: [DatabaseFileProfile] {
        recentProfiles.sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Browse row
                browseRow
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // MARK: Read-only toggle
                readOnlyToggle
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                Divider()

                // MARK: Recent files
                if sortedRecentProfiles.isEmpty {
                    emptyRecentFiles
                } else {
                    recentFilesList
                }

                Spacer(minLength: 0)
            }
            .frame(minWidth: 460, minHeight: 340)
            .navigationTitle("Open SQLite Database")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { commitOpen() }
                        .disabled(pendingFilePath == nil)
                }
            }
        }
    }

    // MARK: - Browse Row

    private var browseRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if let path = pendingFilePath {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file selected")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Browse…") {
                if let path = viewModel.openFilePanel() {
                    pendingFilePath = path
                }
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Read-Only Toggle

    private var readOnlyToggle: some View {
        Toggle("Open read-only", isOn: $viewModel.isReadOnly)
            .font(.system(size: 13))
            .toggleStyle(.checkbox)
    }

    // MARK: - Recent Files

    private var emptyRecentFiles: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No recently opened files")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var recentFilesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List(sortedRecentProfiles) { profile in
                FileOpenRecentRow(profile: profile) {
                    pendingFilePath = profile.filePath
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                .listRowBackground(
                    pendingFilePath == profile.filePath
                        ? Color.accentColor.opacity(0.1)
                        : Color.clear
                )
            }
            .listStyle(.plain)
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Actions

    private func commitOpen() {
        guard let path = pendingFilePath else { return }
        let profile = viewModel.createOrUpdateProfile(
            filePath: path,
            modelContext: modelContext
        )
        dismiss()
        onOpen(profile)
    }
}

// MARK: - FileOpenRecentRow

struct FileOpenRecentRow: View {
    let profile: DatabaseFileProfile
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(profile.filePath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let date = profile.lastOpenedAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
