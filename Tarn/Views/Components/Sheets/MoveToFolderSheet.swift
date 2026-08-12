//
//  MoveToFolderSheet.swift
//  Tarn
//
//  A component for moving queries to folders.
//  Receives data and callbacks - does not access modelContext directly.
//

import SwiftUI

struct MoveToFolderSheet: View {
    let queryCount: Int
    let folders: [QueryFolder]
    let currentFolderIds: Set<UUID?>  // Set of folder IDs the queries are currently in
    let onMoveToFolder: (QueryFolder?) -> Void
    let onCreateFolderAndMove: (String) -> Void
    let onCancel: () -> Void

    @State private var isCreatingNewFolder = false
    @State private var newFolderName = ""
    @FocusState private var isNewFolderFocused: Bool

    /// Check if all queries are in the same folder
    private func allInFolder(_ folderId: UUID?) -> Bool {
        currentFolderIds.count == 1 && currentFolderIds.contains(folderId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(queryCount == 1 ? "Move Query to Folder" : "Move \(queryCount) Queries to Folder")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Folder list
            ScrollView {
                VStack(spacing: 2) {
                    // No folder option (remove from folder)
                    Button {
                        onMoveToFolder(nil)
                    } label: {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundColor(.secondary)
                            Text("No Folder")
                            Spacer()
                            if allInFolder(nil) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Existing folders
                    ForEach(folders.sorted(by: { $0.name < $1.name })) { folder in
                        Button {
                            onMoveToFolder(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(folder.name)
                                Spacer()
                                if allInFolder(folder.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Create new folder option
                    if isCreatingNewFolder {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.secondary)
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .focused($isNewFolderFocused)
                                .onSubmit {
                                    createFolder()
                                }
                            Button("Create") {
                                createFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                isCreatingNewFolder = false
                                newFolderName = ""
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        Button {
                            isCreatingNewFolder = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNewFolderFocused = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(.accentColor)
                                Text("New Folder...")
                                    .foregroundColor(.accentColor)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 350)
    }

    private func createFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        onCreateFolderAndMove(trimmedName)
    }
}
