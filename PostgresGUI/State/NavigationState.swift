//
//  NavigationState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Manages navigation and modal presentation state
@Observable
@MainActor
class NavigationState {
    // Navigation
    var navigationPath: NavigationPath = NavigationPath()

    // Modal/Sheet state
    // NOTE: isShowingConnectionForm / connectionToEdit removed — this is a SQLite-only app;
    //       the Postgres connection form (ConnectionFormView) has been deleted.
    var isShowingCreateDatabase: Bool = false
    var isShowingKeyboardShortcuts: Bool = false
    var isShowingHelp: Bool = false
    var isShowingFileOpen: Bool = false
    var isShowingDiscovery: Bool = false

    // Sheet management helpers
    func showCreateDatabase() {
        isShowingCreateDatabase = true
    }

    func showFileOpen() {
        isShowingFileOpen = true
    }

    func showDiscovery() {
        isShowingDiscovery = true
    }
}
