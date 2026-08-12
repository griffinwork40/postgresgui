//
//  EditFolderSheet.swift
//  Tarn
//
//  A component for renaming query folders.
//  Receives initial name and callbacks - does not mutate models directly.
//

import SwiftUI

struct EditFolderSheet: View {
    let initialName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var folderName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Folder")
                .font(.headline)

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    saveChanges()
                }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            folderName = initialName
        }
    }

    private func saveChanges() {
        let trimmedName = folderName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
    }
}
