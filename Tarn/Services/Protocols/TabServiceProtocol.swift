//
//  TabServiceProtocol.swift
//  Tarn
//
//  Protocol defining the interface for tab state persistence.
//  Enables testability by allowing mock implementations.
//

import Foundation

/// Protocol for tab state management and persistence
@MainActor
protocol TabServiceProtocol {
    /// Load all tabs from persistent storage
    func loadAllTabs() -> [TabState]

    /// Get the currently active tab
    func getActiveTab() -> TabState?

    /// Set a tab as active
    func setActiveTab(_ tab: TabState)

    /// Create a new tab, optionally inheriting from another
    func createTab(inheritingFrom tab: TabState?) -> TabState

    /// Update tab properties
    func updateTab(_ tab: TabState, connectionId: UUID?, databaseName: String?, queryText: String?, savedQueryId: UUID?)

    /// Update tab's selected table
    func updateTabTableSelection(_ tab: TabState, schema: String?, name: String?)

    /// Update tab's cached query results
    func updateTabResults(_ tab: TabState, results: [TableRow]?, columnNames: [String]?)

    /// Clear saved query reference from tab
    func clearSavedQueryId(_ tab: TabState)

    /// Delete a tab
    func deleteTab(_ tab: TabState)

    /// Save changes to persistent storage
    func save()
}
