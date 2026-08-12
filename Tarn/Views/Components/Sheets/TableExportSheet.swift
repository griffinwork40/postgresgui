//
//  TableExportSheet.swift
//  Tarn
//
//  Sheet view for exporting table data in CSV or JSON format
//

import SwiftUI
import UniformTypeIdentifiers

struct TableExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TableContextMenuViewModel

    @State private var selectedFormat: ExportFormat = .csv
    @State private var showExporter = false
    @State private var hasFetchedData = false

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
    }

    /// The content to export based on selected format
    private var exportContent: String {
        switch selectedFormat {
        case .csv:
            return viewModel.csvString
        case .json:
            return viewModel.jsonString
        }
    }

    /// The content type for the file exporter
    private var exportContentType: UTType {
        switch selectedFormat {
        case .csv:
            return .commaSeparatedText
        case .json:
            return .json
        }
    }

    /// The file extension for the export
    private var fileExtension: String {
        switch selectedFormat {
        case .csv:
            return "csv"
        case .json:
            return "json"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isExporting {
                    ProgressView("Fetching table data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.exportRows.isEmpty && hasFetchedData {
                    ContentUnavailableView {
                        Label("No Data", systemImage: "tablecells")
                    } description: {
                        Text("This table has no rows to export.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.exportRows.isEmpty {
                    Form {
                        Section("Export Format") {
                            Picker("Format", selection: $selectedFormat) {
                                ForEach(ExportFormat.allCases, id: \.self) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Preview") {
                            Text("\(viewModel.exportRows.count) row(s) will be exported")
                                .foregroundStyle(.secondary)

                            if !viewModel.exportColumnNames.isEmpty {
                                Text("Columns: \(viewModel.exportColumnNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .formStyle(.grouped)
                } else {
                    // Initial state - data not yet fetched
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Ready to export \(viewModel.table.displayName)")
                            .font(.headline)
                        Text("Click 'Fetch Data' to load the table contents.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Export - \(viewModel.table.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetExportData()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.exportRows.isEmpty && !hasFetchedData {
                        Button("Fetch Data") {
                            Task {
                                await viewModel.fetchDataForExport()
                                hasFetchedData = true
                            }
                        }
                        .disabled(viewModel.isExporting)
                    } else if !viewModel.exportRows.isEmpty {
                        Button("Export \(selectedFormat.rawValue)") {
                            showExporter = true
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(content: exportContent, contentType: exportContentType),
            contentType: exportContentType,
            defaultFilename: "\(viewModel.table.name).\(fileExtension)"
        ) { result in
            if case .success = result {
                viewModel.resetExportData()
                dismiss()
            }
        }
    }
}

// MARK: - Export Document

/// Generic document that can export as CSV or JSON
struct ExportDocument: FileDocument {
    let content: String
    let contentType: UTType

    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }

    init(content: String, contentType: UTType) {
        self.content = content
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}
