//
//  AppLaunchDecisions.swift
//  PostgresGUI
//
//  Pure functions for app launch logic decisions.
//

import Foundation

// MARK: - Decision Functions

/// Determines whether to show the welcome screen
/// - Parameters:
///   - connectionCount: Number of saved PostgreSQL connections
///   - isShowingConnectionForm: Whether connection form is currently showing
///   - fileProfileCount: Number of saved SQLite file profiles (default 0 for backward compatibility)
/// - Returns: True if welcome screen should be shown
func shouldShowWelcomeScreen(
    connectionCount: Int,
    isShowingConnectionForm: Bool,
    fileProfileCount: Int = 0
) -> Bool {
    connectionCount == 0 && fileProfileCount == 0 && !isShowingConnectionForm
}
