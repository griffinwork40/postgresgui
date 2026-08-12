//
//  SafeModeState.swift
//  Tarn
//
//  Observable model tracking whether Safe Mode is active.
//  Safe Mode raises the confirmation threshold and blocks DDL statements entirely.
//

import Foundation
import Observation

// MARK: - Safe Mode State

@Observable
final class SafeModeState {

    // MARK: - State

    var isEnabled: Bool = false

    // MARK: - Confirmation Logic

    /// Whether the given SQL requires a confirmation dialog in the current mode.
    ///
    /// Safe Mode ON:  all writes (INSERT/UPDATE/DELETE/DDL) need confirmation.
    /// Safe Mode OFF: only WHERE-less DELETE/UPDATE and DROP need confirmation.
    func needsConfirmation(for sql: String) -> Bool {
        let level = DestructiveSQLDetector.classify(sql)

        if isEnabled {
            // Block DDL (destructive) entirely — callers should check isBlocked first
            // All write operations require confirmation
            return level >= .caution
        } else {
            // Only dangerous/destructive need a dialog when Safe Mode is off
            return level >= .dangerous
        }
    }

    /// Whether the SQL is outright blocked in Safe Mode (DDL statements).
    /// Returns true only when Safe Mode is ON and the query is destructive.
    func isBlocked(for sql: String) -> Bool {
        guard isEnabled else { return false }
        return DestructiveSQLDetector.classify(sql) == .destructive
    }

    /// The confirmation message to display, if any.
    /// Returns nil when no confirmation is needed.
    func confirmationMessage(for sql: String) -> String? {
        guard needsConfirmation(for: sql) else { return nil }

        // If there's a specific detector message, use it
        if let detectorMessage = DestructiveSQLDetector.warningMessage(for: sql) {
            return detectorMessage
        }

        // Generic write-confirmation message for Safe Mode caution-level queries
        let level = DestructiveSQLDetector.classify(sql)
        if isEnabled && level == .caution {
            return "This query will modify data. Do you want to proceed?"
        }

        return nil
    }

    /// A short label for the toolbar button.
    var toolbarLabel: String {
        isEnabled ? "Safe Mode: On" : "Safe Mode: Off"
    }

    /// System image name for the toolbar button.
    var toolbarIcon: String {
        isEnabled ? "lock.fill" : "lock.open"
    }
}
