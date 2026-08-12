//
//  DetailContentViewModel+Delete.swift
//  PostgresGUI
//

import SwiftUI

extension DetailContentViewModel {

    // MARK: - Delete Operations

    func deleteSelectedRows() {
        DebugLog.print("🗑️ [DetailContentViewModel] Delete button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        if isEditingDisabledDueToContextMismatch {
            deleteError = contextMismatchReason
            return
        }

        // Check if query results are editable (same constraints as edit)
        let editability = queryEditability
        guard editability.isEditable else {
            deleteError = editability.disabledReason
            return
        }

        let resolvedTable: TableInfo? = {
            if let selectedTable = appState.connection.selectedTable {
                return selectedTable
            }

            guard let tableName = editability.tableName else { return nil }
            let candidateTables: [TableInfo]
            if let schemaName = editability.schemaName {
                candidateTables = appState.connection.tables.filter {
                    $0.name == tableName && $0.schema == schemaName
                }
            } else {
                candidateTables = appState.connection.tables.filter { $0.name == tableName }
            }

            return candidateTables.count == 1 ? candidateTables.first : nil
        }()

        guard let selectedTable = resolvedTable else {
            deleteError = EditabilityReason(
                title: "No Table Selected",
                body: "Select a table from the sidebar to delete rows."
            )
            return
        }

        // Validate row selection
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success:
            // Check if we have primary keys cached
            if appState.connection.hasPrimaryKeys(for: selectedTable) {
                let pkColumns = appState.connection.getPrimaryKeys(for: selectedTable)
                tableMetadataService.updateSelectedTableMetadata(
                    connectionState: appState.connection,
                    primaryKeys: pkColumns,
                    columnInfo: nil
                )
                showDeleteConfirmation = true
            } else {
                // Fetch primary keys if not cached
                Task {
                    await fetchPrimaryKeysAndShowDeleteDialog(table: selectedTable)
                }
            }
        case .failure(let error):
            deleteError = EditabilityReason(
                title: "Selection Error",
                body: error.localizedDescription
            )
        }
    }

    func fetchPrimaryKeysAndShowDeleteDialog(table: TableInfo) async {
        let result = await fetchMetadataAndExecute(table: table) { updatedTable in
            updatedTable
        }

        switch result {
        case .success(let updatedTable):
            guard let pkColumns = updatedTable.primaryKeyColumns, !pkColumns.isEmpty else {
                deleteError = EditabilityReason(
                    title: "Can't Identify Row",
                    body: "This table has no primary key. Row deletion requires a way to uniquely identify each row."
                )
                return
            }
            showDeleteConfirmation = true
        case .failure(let error):
            deleteError = EditabilityReason(
                title: "Metadata Error",
                body: error.localizedDescription
            )
        }
    }

    func performDelete() async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        // Get selected rows with their indices for potential rollback
        let deletedIDs = appState.query.selectedRowIDs
        let rowsWithIndices: [(index: Int, row: TableRow)] = appState.query.queryResults
            .enumerated()
            .filter { deletedIDs.contains($0.element.id) }
            .map { (index: $0.offset, row: $0.element) }

        guard !rowsWithIndices.isEmpty else { return }

        // Capture results version before async operation
        let versionBeforeDelete = appState.query.resultsVersion
        // Optimistic UI update: remove rows immediately
        appState.query.queryResults.removeAll { deletedIDs.contains($0.id) }
        appState.query.selectedRowIDs = []

        // Perform backend delete
        let result = await rowOperations.deleteRows(
            table: selectedTable,
            rows: rowsWithIndices.map { $0.row },
            databaseService: appState.connection.databaseService
        )

        let isSuccess: Bool
        switch result {
        case .success:
            isSuccess = true
        case .failure:
            isSuccess = false
        }
        let canRollback = !isSuccess
            ? isSafeToRollback(versionAtOperationStart: versionBeforeDelete, currentVersion: appState.query.resultsVersion)
            : false
        // Rollback on failure (only if results haven't been replaced by a refresh)
        if case .failure(let error) = result {
            if canRollback {
                // Safe to rollback - results haven't changed
                for (index, row) in rowsWithIndices.sorted(by: { $0.index < $1.index }) {
                    let insertIndex = min(index, appState.query.queryResults.count)
                    appState.query.queryResults.insert(row, at: insertIndex)
                }
            }
            deleteError = EditabilityReason(
                title: "Delete Failed",
                body: error.localizedDescription
            )
        }
    }
}
