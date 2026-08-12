//
//  AttachedDatabasesView.swift
//  PostgresGUI
//
//  Sheet for managing SQLite attached databases.
//  Lists current attachments (including the always-present "main"),
//  lets the user attach new files and detach user-added ones.
//

import SwiftUI

// MARK: - AttachedDatabasesView

struct AttachedDatabasesView: View {
    @Environment(\.dismiss) private var dismiss

    /// The owning state object — passed in from the toolbar / sidebar action.
    @State private var viewModel: AttachedDatabaseViewModel

    /// Alias field for the "Attach Database" form.
    @State private var pendingAlias: String = ""

    /// Controls whether the inline attach form is visible.
    @State private var showAttachForm: Bool = false

    init(service: SQLiteDatabaseService) {
        _viewModel = State(initialValue: AttachedDatabaseViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                attachErrorBanner()
                databaseList()
            }
            .navigationTitle("Attached Databases")
            .toolbar { toolbarItems() }
        }
        .frame(minWidth: 480, minHeight: 400)
        .task { await viewModel.refresh() }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func attachErrorBanner() -> some View {
        if let msg = viewModel.errorMessage {
            HStack {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    viewModel.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.red.opacity(0.08))
        }
    }

    // MARK: - Database List

    @ViewBuilder
    private func databaseList() -> some View {
        List {
            if showAttachForm {
                attachFormSection()
            }

            ForEach(viewModel.attachedDatabases) { attached in
                attachedDatabaseSection(attached)
            }

            if viewModel.attachedDatabases.isEmpty && !viewModel.isBusy {
                ContentUnavailableView(
                    "No Databases Attached",
                    systemImage: "externaldrive.badge.plus",
                    description: Text("Tap \"Attach Database…\" to link an external SQLite file.")
                )
            }
        }
        .listStyle(.inset)
        .overlay {
            if viewModel.isBusy {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Attach Form

    @ViewBuilder
    private func attachFormSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("New attachment alias")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("e.g. logs", text: $pendingAlias)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if let msg = viewModel.aliasValidationMessage(for: pendingAlias) {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") {
                        pendingAlias = ""
                        showAttachForm = false
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("Choose File…") {
                        Task {
                            await viewModel.attach(alias: pendingAlias)
                            if viewModel.errorMessage == nil {
                                pendingAlias = ""
                                showAttachForm = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isAliasValid(pendingAlias))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Attach Database", systemImage: "externaldrive.badge.plus")
        }
    }

    // MARK: - Per-Database Section

    @ViewBuilder
    private func attachedDatabaseSection(_ attached: AttachedDatabase) -> some View {
        Section {
            // Header row: alias + file info
            databaseHeaderRow(attached)

            // Table list — load on first expansion
            let tables = viewModel.tablesByAlias[attached.alias]
            if let tables = tables {
                if tables.isEmpty {
                    Text("No tables or views")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                } else {
                    ForEach(tables) { table in
                        tableRow(table)
                    }
                }
            } else {
                Button("Load Tables") {
                    Task { await viewModel.loadTables(for: attached.alias) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.leading, 8)
            }
        } header: {
            databaseSectionHeader(attached)
        }
    }

    @ViewBuilder
    private func databaseSectionHeader(_ attached: AttachedDatabase) -> some View {
        HStack {
            Label {
                Text(attached.alias)
                    .fontWeight(attached.isMain ? .semibold : .regular)
            } icon: {
                Image(systemName: attached.isMain ? "internaldrive" : "externaldrive")
                    .foregroundStyle(attached.isMain ? .blue : .secondary)
            }

            Spacer()

            if !attached.isReserved {
                Button(role: .destructive) {
                    Task { await viewModel.detach(alias: attached.alias) }
                } label: {
                    Text("Detach")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(viewModel.isBusy)
            }
        }
    }

    @ViewBuilder
    private func databaseHeaderRow(_ attached: AttachedDatabase) -> some View {
        LabeledContent("File") {
            Text(attached.filePath.isEmpty ? attached.displayFileName : attached.displayFileName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        if let tables = viewModel.tablesByAlias[attached.alias] {
            LabeledContent("Objects") {
                Text("\(tables.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func tableRow(_ table: TableInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: table.tableType == .view ? "eye" : "tablecells")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(table.name)
                .font(.callout)
            Spacer()
            Text(table.tableType.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarItems() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isBusy)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showAttachForm.toggle()
                if !showAttachForm { pendingAlias = "" }
            } label: {
                Label("Attach Database…", systemImage: "externaldrive.badge.plus")
            }
            .disabled(viewModel.isBusy)
        }
    }
}
