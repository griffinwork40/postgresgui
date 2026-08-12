//
//  BlobInspectorView.swift
//  PostgresGUI
//
//  Sheet UI for inspecting a raw BLOB cell value.
//  Renders images directly; other types get a hex dump with ASCII sidebar.
//

import SwiftUI
import AppKit

// MARK: - BlobInspectorView

struct BlobInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let inspection: BlobInspection
    let columnName: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                metadataBar
                Divider()
                contentArea
            }
            .navigationTitle("BLOB — \(columnName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save to File…") { saveToFile() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - Metadata bar

    private var metadataBar: some View {
        HStack(spacing: 12) {
            // Type badge
            Label(inspection.contentType.badgeLabel,
                  systemImage: inspection.contentType.systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 5))

            Text(inspection.formattedSize)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        switch inspection.contentType {
        case .image:
            imageView
        default:
            HexDumpView(data: inspection.data)
        }
    }

    // MARK: - Image rendering

    private var imageView: some View {
        Group {
            if let nsImage = NSImage(data: inspection.data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: nsImage.size.width,
                            maxHeight: nsImage.size.height
                        )
                        .padding(16)
                }
            } else {
                // Decoding failed — fall through to hex dump
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Could not decode image data")
                        .foregroundStyle(.secondary)
                    HexDumpView(data: inspection.data)
                }
            }
        }
    }

    // MARK: - Helpers

    private var badgeColor: Color {
        switch inspection.contentType {
        case .image:      return .blue
        case .pdf:        return .red
        case .zip:        return .orange
        case .sqlite:     return .purple
        case .unknown:    return .secondary
        }
    }

    // MARK: - Save panel

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "\(columnName)_blob.\(inspection.contentType.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try inspection.data.write(to: url, options: .atomic)
        } catch {
            // Surface error via standard alert — sheet is still presented
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
