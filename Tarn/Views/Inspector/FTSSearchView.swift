//
//  FTSSearchView.swift
//  Tarn
//
//  Inspector panel for searching FTS virtual tables.
//  Follows the HealthInspectorView pattern: NavigationStack + Form + .formStyle(.grouped).
//

import SwiftUI

// MARK: - FTSSearchView

struct FTSSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FTSSearchViewModel

    init(service: SQLiteDatabaseService) {
        _viewModel = State(initialValue: FTSSearchViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    ProgressView("Loading FTS tables…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    ContentUnavailableView(
                        "Unable to Load FTS Tables",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                case .loaded(let tables):
                    if tables.isEmpty {
                        noFTSTablesView
                    } else {
                        searchPanel(tables: tables)
                    }
                }
            }
            .navigationTitle("FTS Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .task { await viewModel.loadFTSTables() }
    }

    // MARK: - No Tables Placeholder

    private var noFTSTablesView: some View {
        ContentUnavailableView(
            "No FTS Tables",
            systemImage: "magnifyingglass",
            description: Text("This database contains no Full-Text Search virtual tables.")
        )
    }

    // MARK: - Search Panel

    @ViewBuilder
    private func searchPanel(tables: [FTSTableInfo]) -> some View {
        Form {
            tablePickerSection(tables)

            if let table = viewModel.selectedTable {
                tableInfoSection(table)
            }

            searchSection()
            resultsSection()
        }
        .formStyle(.grouped)
    }

    // MARK: - Table Picker Section

    @ViewBuilder
    private func tablePickerSection(_ tables: [FTSTableInfo]) -> some View {
        Section {
            Picker("FTS Table", selection: $viewModel.selectedTable) {
                ForEach(tables) { table in
                    Text(table.name).tag(Optional(table))
                }
            }
            .onChange(of: viewModel.selectedTable) { _, _ in
                viewModel.clearSearch()
            }
        } header: {
            Label("Table", systemImage: "tablecells")
        }
    }

    // MARK: - Table Info Section

    @ViewBuilder
    private func tableInfoSection(_ table: FTSTableInfo) -> some View {
        Section {
            FTSInfoRow(label: "Module", value: table.module.displayName)

            if let tok = table.tokenizer {
                FTSInfoRow(label: "Tokenizer", value: tok)
            }

            if let content = table.contentTable {
                FTSInfoRow(label: "Content table", value: content)
            }

            if !table.indexedColumns.isEmpty {
                FTSInfoRow(label: "Indexed columns",
                           value: table.indexedColumns.joined(separator: ", "))
            }

            if table.module.supportsBM25 {
                FTSInfoRow(label: "Ranking", value: "BM25 (built-in)")
            }
        } header: {
            Label("Table Info", systemImage: "info.circle")
        }
    }

    // MARK: - Search Section

    @ViewBuilder
    private func searchSection() -> some View {
        Section {
            HStack {
                TextField("Search…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard viewModel.canSearch else { return }
                        Task { await viewModel.search() }
                    }

                Button {
                    Task { await viewModel.search() }
                } label: {
                    if viewModel.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                .disabled(!viewModel.canSearch || viewModel.isSearching)
                .buttonStyle(.bordered)

                if case .results = viewModel.searchState {
                    Button("Clear") { viewModel.clearSearch() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Search", systemImage: "magnifyingglass")
        } footer: {
            Text("Use FTS MATCH syntax: \"hello world\", \"hello OR world\", \"hello*\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private func resultsSection() -> some View {
        switch viewModel.searchState {
        case .idle:
            EmptyView()

        case .searching:
            Section {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching…").foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            Section {
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } header: {
                Label("Error", systemImage: "exclamationmark.triangle")
            }

        case .results(let result):
            Section {
                if result.rows.isEmpty {
                    Text("No matches found.")
                        .foregroundStyle(.secondary)
                } else {
                    FTSResultsTable(result: result)
                }
            } header: {
                Label(
                    "Results — \(viewModel.resultCountLabel)",
                    systemImage: "list.bullet"
                )
            } footer: {
                Text(String(format: "Query completed in %.3fs", result.executionTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - FTSInfoRow

/// A two-column label/value row for the FTS info section.
private struct FTSInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - FTSResultsTable

/// Scrollable table showing FTS search results.
private struct FTSResultsTable: View {
    let result: QueryResult

    private static let maxRows = 200

    private var displayedRows: [TableRow] {
        Array(result.rows.prefix(Self.maxRows))
    }

    private var isTruncated: Bool {
        result.rows.count > Self.maxRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    headerRow

                    Divider()

                    // Data rows
                    ForEach(displayedRows) { row in
                        FTSDataRow(row: row, columns: result.columnNames)
                        Divider()
                    }
                }
            }

            if isTruncated {
                Text("Showing first \(Self.maxRows) of \(result.rows.count) rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(result.columnNames, id: \.self) { col in
                Text(col)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - FTSDataRow

private struct FTSDataRow: View {
    let row: TableRow
    let columns: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { col in
                Text(row.values[col].flatMap { $0 } ?? "NULL")
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
        }
    }
}
