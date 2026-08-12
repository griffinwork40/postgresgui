//
//  EditQuerySheet.swift
//  Tarn
//
//  A component for renaming saved queries.
//  Receives initial name and callbacks - does not mutate models directly.
//

import SwiftUI

struct EditQuerySheet: View {
    let initialName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var editedName: String = ""

    private var canSave: Bool {
        !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Query")
                .font(.headline)

            TextField("Query Name", text: $editedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSave { save() } }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { editedName = initialName }
    }

    private func save() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
    }
}
