//
//  CellJSONInspectorView.swift
//  PostgresGUI
//
//  Sheet view for inspecting a single cell's JSON content.
//  Displays pretty-printed JSON with copy and export actions.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CellJSONInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let columnName: String
    let rawValue: String
    let prettyJSON: String

    @State private var showingExporter = false
    @State private var showCopiedIcon = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(prettyJSON)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("JSON — \(columnName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 8) {
                        Button("Export JSON…") {
                            showingExporter = true
                        }

                        Button {
                            handleCopyJSON()
                        } label: {
                            Label {
                                Text("Copy")
                            } icon: {
                                ZStack {
                                    Image(systemName: "doc.on.doc")
                                        .opacity(showCopiedIcon ? 0 : 1)
                                    Image(systemName: "checkmark")
                                        .opacity(showCopiedIcon ? 1 : 0)
                                }
                                .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
        .fileExporter(
            isPresented: $showingExporter,
            document: JSONDocument(content: prettyJSON),
            contentType: .json,
            defaultFilename: "\(columnName)_value"
        ) { _ in }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private func handleCopyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prettyJSON, forType: .string)

        showCopiedIcon = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_750_000_000)
            guard !Task.isCancelled else { return }
            showCopiedIcon = false
            copyFeedbackTask = nil
        }
    }
}
