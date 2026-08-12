//
//  TableContextMenuViewModel.swift
//  Tarn
//
//  ViewModel for table context menu operations (DDL, Truncate, Drop, Export)
//

import SwiftUI
import AppKit

/// ViewModel managing state and actions for the table context menu
@Observable
@MainActor
class TableContextMenuViewModel {

    // MARK: - Dependencies

    let table: TableInfo
    private weak var appState: AppState?

    // MARK: - Modal State

    var showDDLSheet = false
    var showExportSheet = false
    var showTruncateConfirmation = false
    var showDropConfirmation = false

    // MARK: - Loading State

    var isGeneratingDDL = false
    var isExporting = false
    var isTruncating = false
    var isDropping = false

    // MARK: - Data

    var generatedDDL: String = ""
    var exportRows: [TableRow] = []
    var exportColumnNames: [String] = []

    // MARK: - Error State

    var errorMessage: String?
    var showError = false

    // MARK: - Initialization

    init(table: TableInfo, appState: AppState?) {
        self.table = table
        self.appState = appState
    }

    // MARK: - DDL Generation

    func generateDDL() async {
        guard let appState = appState else { return }

        isGeneratingDDL = true
        defer { isGeneratingDDL = false }

        do {
            let databaseService = appState.connection.databaseService
            generatedDDL = try await databaseService.generateDDL(schema: table.schema, table: table.name)
            showDDLSheet = true
        } catch {
            errorMessage = "Failed to generate DDL: \(error.localizedDescription)"
            showError = true
        }
    }

    func copyDDLToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(generatedDDL, forType: .string)
    }

    // MARK: - Truncate

    func truncateTable() async {
        guard let appState = appState else { return }

        isTruncating = true
        defer { isTruncating = false }

        do {
            let databaseService = appState.connection.databaseService
            try await databaseService.truncateTable(schema: table.schema, table: table.name)

            // If this was the selected table, refresh its data
            if appState.connection.selectedTable?.id == table.id {
                await appState.executeTableQuery(for: table)
            }
        } catch {
            errorMessage = "Failed to truncate table: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Drop

    func dropTable() async {
        guard let appState = appState else { return }

        isDropping = true
        defer { isDropping = false }

        do {
            let databaseService = appState.connection.databaseService
            try await databaseService.deleteTable(schema: table.schema, table: table.name)

            // Clear selection if this was the selected table
            if appState.connection.selectedTable?.id == table.id {
                appState.connection.selectedTable = nil
                appState.query.clearQueryResults()
            }

            // Refresh the tables list
            if let database = appState.connection.selectedDatabase {
                appState.connection.tables = try await databaseService.fetchTables(database: database.name)
            }
        } catch {
            errorMessage = "Failed to drop table: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Export

    func fetchDataForExport() async {
        guard let appState = appState else { return }

        isExporting = true
        defer { isExporting = false }

        do {
            let databaseService = appState.connection.databaseService
            let (rows, columnNames) = try await databaseService.fetchAllTableData(
                schema: table.schema,
                table: table.name
            )
            exportRows = rows
            exportColumnNames = columnNames
        } catch {
            errorMessage = "Failed to fetch table data: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Generate CSV string from export data
    var csvString: String {
        CSVExporter.toCSV(rows: exportRows, columns: exportColumnNames)
    }

    /// Generate JSON string from export data
    var jsonString: String {
        let rowsAsDicts = exportRows.map { row in
            row.values.mapValues { value -> Any in
                if let stringValue = value {
                    return stringValue
                } else {
                    return NSNull()
                }
            }
        }

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: rowsAsDicts,
                options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            return "Error encoding JSON: \(error.localizedDescription)"
        }
    }

    /// Reset export data when sheet is dismissed
    func resetExportData() {
        exportRows = []
        exportColumnNames = []
    }
}
