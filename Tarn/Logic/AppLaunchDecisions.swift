//
//  AppLaunchDecisions.swift
//  Tarn
//
//  Pure functions for app launch logic decisions.
//

import Foundation

// MARK: - Decision Functions

/// Determines whether to show the welcome screen
/// - Parameters:
///   - connectionCount: Number of saved PostgreSQL connections (legacy; not used in SQLite-only build)
///   - fileProfileCount: Number of saved SQLite file profiles
/// - Returns: True if welcome screen should be shown
func shouldShowWelcomeScreen(
    connectionCount: Int,
    fileProfileCount: Int = 0
) -> Bool {
    connectionCount == 0 && fileProfileCount == 0
}
