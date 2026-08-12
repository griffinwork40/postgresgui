//
//  HealthInspectorView.swift
//  Tarn
//
//  PRAGMA-based database health dashboard with maintenance actions.
//

import SwiftUI

// MARK: - HealthInspectorView

struct HealthInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HealthInspectorViewModel

    // Confirmation-dialog flags
    @State private var showVacuumConfirm   = false
    @State private var showAnalyzeConfirm  = false
    @State private var showIntegrityConfirm = false

    init(service: SQLiteDatabaseService) {
        _viewModel = State(initialValue: HealthInspectorViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle:
                    ProgressView("Loading health data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loading:
                    ProgressView("Loading health data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    ContentUnavailableView(
                        "Unable to Load Health Data",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                case .loaded(let health):
                    healthDashboard(health)
                }
            }
            .navigationTitle("Database Health")
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
                    .disabled(isRefreshDisabled)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 620)
        .task { await viewModel.refresh() }
    }

    // MARK: - Dashboard body

    @ViewBuilder
    private func healthDashboard(_ health: DatabaseHealth) -> some View {
        Form {
            storageSection(health)
            schemaSection(health)
            configSection(health)
            maintenanceSection()
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    @ViewBuilder
    private func storageSection(_ h: DatabaseHealth) -> some View {
        Section {
            HealthRow(label: "File size",
                      value: h.fileSizeBytes > 0
                             ? viewModel.formattedFileSize(h.fileSizeBytes)
                             : "In-memory")

            HealthRow(label: "Page size",
                      value: "\(h.pageCount.formatted()) pages × \(h.pageSize.formatted()) bytes")

            HealthRow(label: "Free pages",
                      value: "\(h.freePageCount.formatted()) (\(viewModel.formattedFragmentation(h.fragmentationPercent)))",
                      valueColor: h.fragmentationPercent > 20 ? .orange : nil)

            HealthRow(label: "Journal mode", value: h.journalMode.uppercased())

            HealthRow(label: "WAL file", value: h.walFile ? "Present" : "None")

            if let walPages = h.walPages {
                HealthRow(label: "WAL pages", value: walPages.formatted())
            }

            HealthRow(label: "Auto-vacuum", value: h.autoVacuum.displayName)
        } header: {
            Label("Storage", systemImage: "externaldrive")
        }
    }

    @ViewBuilder
    private func schemaSection(_ h: DatabaseHealth) -> some View {
        Section {
            HStack(spacing: 20) {
                SchemaStatBox(label: "Tables",   count: h.tableCount)
                SchemaStatBox(label: "Indexes",  count: h.indexCount)
                SchemaStatBox(label: "Views",    count: h.viewCount)
                SchemaStatBox(label: "Triggers", count: h.triggerCount)
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Label("Schema", systemImage: "list.clipboard")
        }
    }

    @ViewBuilder
    private func configSection(_ h: DatabaseHealth) -> some View {
        Section {
            HealthRow(label: "Encoding",     value: h.encoding)
            HealthRow(label: "Foreign keys", value: h.foreignKeysEnabled ? "Enabled" : "Disabled")
            HealthRow(label: "Cache size",   value: "\(h.cacheSize.formatted()) pages")
            HealthRow(label: "Memory map",   value: viewModel.formattedMmapSize(h.mmapSize))
        } header: {
            Label("Configuration", systemImage: "gearshape")
        }
    }

    @ViewBuilder
    private func maintenanceSection() -> some View {
        Section {
            // Action buttons row
            HStack(spacing: 12) {
                MaintenanceButton(
                    title: "Integrity Check",
                    systemImage: "checkmark.shield",
                    action: { showIntegrityConfirm = true }
                )
                MaintenanceButton(
                    title: "VACUUM",
                    systemImage: "trash.slash",
                    action: { showVacuumConfirm = true }
                )
                MaintenanceButton(
                    title: "ANALYZE",
                    systemImage: "chart.bar",
                    action: { showAnalyzeConfirm = true }
                )
                Spacer()
            }
            .padding(.vertical, 4)

            // Action status feedback
            actionStatusRow()

            // Last integrity-check result detail
            if let result = viewModel.lastIntegrityResult {
                integrityResultRow(result)
            }
        } header: {
            Label("Maintenance", systemImage: "wrench.and.screwdriver")
        }
        // Confirmation dialogs
        .confirmationDialog(
            "Run VACUUM?",
            isPresented: $showVacuumConfirm,
            titleVisibility: .visible
        ) {
            Button("VACUUM", role: .destructive) {
                Task { await viewModel.runVacuum() }
            }
        } message: {
            Text("VACUUM rebuilds the database file to reclaim free pages. This may take a moment on large databases.")
        }
        .confirmationDialog(
            "Run ANALYZE?",
            isPresented: $showAnalyzeConfirm,
            titleVisibility: .visible
        ) {
            Button("ANALYZE") {
                Task { await viewModel.runAnalyze() }
            }
        } message: {
            Text("ANALYZE updates query planner statistics. This is safe and fast.")
        }
        .confirmationDialog(
            "Run Integrity Check?",
            isPresented: $showIntegrityConfirm,
            titleVisibility: .visible
        ) {
            Button("Run Check") {
                Task { await viewModel.runIntegrityCheck() }
            }
        } message: {
            Text("Integrity check scans the entire database for structural errors. It may be slow on large files.")
        }
    }

    @ViewBuilder
    private func actionStatusRow() -> some View {
        switch viewModel.actionState {
        case .idle:
            EmptyView()
        case .running(let msg):
            HStack {
                ProgressView().controlSize(.small)
                Text(msg).foregroundStyle(.secondary)
            }
        case .succeeded(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func integrityResultRow(_ result: IntegrityCheckResult) -> some View {
        HStack {
            if result.isOK {
                Label("OK (\(viewModel.formattedDuration(result.duration)))",
                      systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(result.messages.count) error(s) found",
                      systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var isRefreshDisabled: Bool {
        if case .loading = viewModel.loadState { return true }
        if case .running = viewModel.actionState { return true }
        return false
    }
}

// MARK: - Sub-components

/// A two-column label/value row for the health dashboard.
private struct HealthRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(valueColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A compact numeric stat box used in the schema section.
private struct SchemaStatBox: View {
    let label: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count.formatted())
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60, alignment: .leading)
    }
}

/// A compact button for maintenance actions.
private struct MaintenanceButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
        }
        .buttonStyle(.bordered)
    }
}
