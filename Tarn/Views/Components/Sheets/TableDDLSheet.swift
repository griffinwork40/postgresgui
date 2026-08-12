//
//  TableDDLSheet.swift
//  Tarn
//
//  Sheet view for displaying table DDL with copy functionality
//

import SwiftUI
import AppKit

struct TableDDLSheet: View {
    @Environment(\.dismiss) private var dismiss
    let ddl: String
    let tableName: String
    let onCopy: () -> Void

    @State private var showCopiedFeedback = false

    var body: some View {
        NavigationStack {
            TextEditor(text: Binding(
                get: { ddl },
                set: { _ in } // Read-only
            ))
            .font(.system(.body, design: .monospaced))
            .navigationTitle("DDL - \(tableName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCopy()
                        showCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedFeedback = false
                        }
                    } label: {
                        if showCopiedFeedback {
                            Label("Copied!", systemImage: "checkmark")
                        } else {
                            Label("Copy DDL", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}
