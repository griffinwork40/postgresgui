//
//  SchemaVisualizationView.swift
//  Tarn
//
//  Schema relationship browser: lists all tables with FK indicators and
//  lets the user drill into a table's inbound / outbound relationships.
//

import SwiftUI

// MARK: - SchemaVisualizationView

struct SchemaVisualizationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SchemaVisualizationViewModel

    init(service: SQLiteDatabaseService) {
        _viewModel = State(initialValue: SchemaVisualizationViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle:
                    ProgressView("Loading schema…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loading:
                    ProgressView("Loading schema…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    ContentUnavailableView(
                        "Unable to Load Schema",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                case .loaded(let overview):
                    schemaContent(overview)
                }
            }
            .navigationTitle("Schema Relationships")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled({
                        if case .loading = viewModel.loadState { return true }
                        return false
                    }())
                }
            }
        }
        .frame(minWidth: 560, minHeight: 500)
        .task { await viewModel.refresh() }
    }

    // MARK: - Main content

    @ViewBuilder
    private func schemaContent(_ overview: SchemaOverview) -> some View {
        if overview.tables.isEmpty {
            ContentUnavailableView(
                "No Tables Found",
                systemImage: "tablecells",
                description: Text("This database contains no user tables.")
            )
        } else {
            HSplitView {
                tableList(overview)
                    .frame(minWidth: 200, maxWidth: 260)
                detailPanel(overview)
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Left panel: table list

    @ViewBuilder
    private func tableList(_ overview: SchemaOverview) -> some View {
        List(overview.tables, selection: $viewModel.selectedTable) { table in
            SchemaTableRow(table: table, hasRelationships: overview.hasRelationships(table))
                .tag(table)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Right panel: relationship detail

    @ViewBuilder
    private func detailPanel(_ overview: SchemaOverview) -> some View {
        if let table = viewModel.selectedTable {
            tableDetail(table, overview: overview)
        } else {
            noSelectionPlaceholder(overview)
        }
    }

    @ViewBuilder
    private func noSelectionPlaceholder(_ overview: SchemaOverview) -> some View {
        if overview.relationships.isEmpty {
            ContentUnavailableView(
                "No Foreign Keys",
                systemImage: "link.badge.xmark",
                description: Text("This database has no foreign-key relationships defined.")
            )
        } else {
            ContentUnavailableView(
                "Select a Table",
                systemImage: "arrow.left",
                description: Text("Choose a table on the left to see its relationships.")
            )
        }
    }

    @ViewBuilder
    private func tableDetail(_ table: SchemaTable, overview: SchemaOverview) -> some View {
        let outbound = overview.outbound(from: table)
        let inbound  = overview.inbound(to: table)

        Form {
            // Table metadata
            Section {
                LabeledContent("Name", value: table.name)
                if !table.primaryKeys.isEmpty {
                    LabeledContent("Primary Key", value: table.primaryKeys.joined(separator: ", "))
                }
                LabeledContent("Columns", value: table.columnCount.formatted())
                if let rowCount = table.rowCount {
                    LabeledContent("Rows", value: rowCount.formatted())
                }
            } header: {
                Label("Table Info", systemImage: "tablecells")
            }

            // Outbound FKs (this table → other tables)
            if !outbound.isEmpty {
                Section {
                    ForEach(outbound) { rel in
                        RelationshipRow(
                            label: "\(rel.sourceColumn)",
                            arrow: "→",
                            target: "\(rel.targetTable).\(rel.targetColumn)"
                        )
                    }
                } header: {
                    Label("References (outbound)", systemImage: "arrow.up.right")
                }
            }

            // Inbound FKs (other tables → this table)
            if !inbound.isEmpty {
                Section {
                    ForEach(inbound) { rel in
                        RelationshipRow(
                            label: "\(rel.sourceTable).\(rel.sourceColumn)",
                            arrow: "→",
                            target: "\(rel.targetColumn)"
                        )
                    }
                } header: {
                    Label("Referenced by (inbound)", systemImage: "arrow.down.left")
                }
            }

            // No relationships at all
            if outbound.isEmpty && inbound.isEmpty {
                Section {
                    Text("No foreign-key relationships")
                        .foregroundStyle(.secondary)
                        .italic()
                } header: {
                    Label("Relationships", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sub-components

/// A row in the table list showing name + relationship indicator badge.
private struct SchemaTableRow: View {
    let table: SchemaTable
    let hasRelationships: Bool

    var body: some View {
        HStack {
            Image(systemName: "tablecells")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(table.name)
                    .lineLimit(1)
                Text("\(table.columnCount) col\(table.columnCount == 1 ? "" : "s")" +
                     (table.primaryKeys.isEmpty ? "" : " · PK: \(table.primaryKeys.joined(separator: ","))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if hasRelationships {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A single FK arrow row: source → target.
private struct RelationshipRow: View {
    let label: String
    let arrow: String
    let target: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            Text(arrow)
                .foregroundStyle(.secondary)
            Text(target)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.blue)
            Spacer()
        }
    }
}
