//
//  TableContextMenuModals.swift
//  Tarn
//
//  ViewModifier that adds all modals and dialogs for table context menu operations
//

import SwiftUI

/// ViewModifier that attaches all table context menu modals to a view
struct TableContextMenuModals: ViewModifier {
    @Bindable var viewModel: TableContextMenuViewModel
    let onTableDropped: () async -> Void

    func body(content: Content) -> some View {
        content
            // DDL Sheet
            .sheet(isPresented: $viewModel.showDDLSheet) {
                TableDDLSheet(
                    ddl: viewModel.generatedDDL,
                    tableName: viewModel.table.displayName,
                    onCopy: { viewModel.copyDDLToClipboard() }
                )
            }
            // Export Sheet
            .sheet(isPresented: $viewModel.showExportSheet) {
                TableExportSheet(viewModel: viewModel)
            }
            // Truncate Confirmation Dialog
            .confirmationDialog(
                "Truncate Table?",
                isPresented: $viewModel.showTruncateConfirmation
            ) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.truncateTable()
                    }
                } label: {
                    Text("Truncate")
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showTruncateConfirmation = false
                }
            } message: {
                Text("Are you sure you want to truncate \"\(viewModel.table.displayName)\"? This will delete all rows in the table. This action cannot be undone.")
            }
            // Drop Confirmation Dialog
            .confirmationDialog(
                "Drop Table?",
                isPresented: $viewModel.showDropConfirmation
            ) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.dropTable()
                        await onTableDropped()
                    }
                } label: {
                    Text("Drop")
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showDropConfirmation = false
                }
            } message: {
                Text("Are you sure you want to drop \"\(viewModel.table.displayName)\"? This will permanently delete the table and all its data. This action cannot be undone.")
            }
            // Error Alert
            .alert(
                "Error",
                isPresented: $viewModel.showError
            ) {
                Button("OK", role: .cancel) {
                    viewModel.showError = false
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Apply all table context menu modals to this view
    func tableContextMenuModals(
        viewModel: TableContextMenuViewModel,
        onTableDropped: @escaping () async -> Void
    ) -> some View {
        modifier(TableContextMenuModals(viewModel: viewModel, onTableDropped: onTableDropped))
    }
}
