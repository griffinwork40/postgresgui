//
//  SafeModeToolbarItem.swift
//  Tarn
//
//  Toolbar button that toggles Safe Mode and shows the confirmation dialog
//  for dangerous SQL before execution proceeds.
//

import SwiftUI

// MARK: - Safe Mode Toolbar Button

/// A `ToolbarContent` group that renders the Safe Mode toggle.
/// Drop this into any toolbar that has access to a `SafeModeState`.
struct SafeModeToolbarButton: ToolbarContent {
    @Bindable var safeModeState: SafeModeState

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                safeModeState.isEnabled.toggle()
            } label: {
                Label(safeModeState.toolbarLabel,
                      systemImage: safeModeState.toolbarIcon)
                    .foregroundStyle(safeModeState.isEnabled ? .orange : .secondary)
            }
            .help(safeModeState.isEnabled
                ? "Safe Mode is ON — DDL blocked, writes require confirmation. Click to disable."
                : "Safe Mode is OFF. Click to enable write confirmation and DDL blocking.")
            .tint(safeModeState.isEnabled ? .orange : nil)
            .accessibilityIdentifier("safeModeToggle")
        }
    }
}

// MARK: - Query Confirmation Dialog Modifier

/// View modifier that presents a confirmation alert before running dangerous SQL.
///
/// Usage:
/// ```swift
/// myView
///     .queryConfirmation(state: safeModeState, pendingSQL: $pendingSQL) {
///         Task { await runQuery() }
///     }
/// ```
struct QueryConfirmationModifier: ViewModifier {
    let safeModeState: SafeModeState
    @Binding var pendingSQL: String?
    let onConfirm: () -> Void

    private var isPresented: Binding<Bool> {
        Binding(
            get: { pendingSQL != nil },
            set: { if !$0 { pendingSQL = nil } }
        )
    }

    private var alertTitle: String {
        guard let sql = pendingSQL else { return "" }
        let level = DestructiveSQLDetector.classify(sql)
        switch level {
        case .destructive: return "Destructive Operation"
        case .dangerous:   return "Dangerous Operation"
        case .caution:     return "Confirm Write"
        case .safe:        return "Confirm"
        }
    }

    private var alertMessage: String {
        guard let sql = pendingSQL else { return "" }
        if let msg = safeModeState.confirmationMessage(for: sql) {
            return msg
        }
        // Fallback: show a snippet of the SQL
        let preview = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        return "SQL:\n\(snippet)"
    }

    func body(content: Content) -> some View {
        content
            .alert(alertTitle, isPresented: isPresented) {
                Button("Cancel", role: .cancel) {
                    pendingSQL = nil
                }
                Button("Proceed", role: .destructive) {
                    pendingSQL = nil
                    onConfirm()
                }
            } message: {
                Text(alertMessage)
            }
    }
}

extension View {
    /// Attach the query confirmation dialog to any view.
    func queryConfirmation(
        state: SafeModeState,
        pendingSQL: Binding<String?>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(QueryConfirmationModifier(
            safeModeState: state,
            pendingSQL: pendingSQL,
            onConfirm: onConfirm
        ))
    }
}

// MARK: - Safe Mode Blocked Alert Modifier

/// Presents an alert when Safe Mode blocks a DDL statement outright.
struct SafeModeBlockedModifier: ViewModifier {
    @Binding var blockedSQL: String?

    private var isPresented: Binding<Bool> {
        Binding(
            get: { blockedSQL != nil },
            set: { if !$0 { blockedSQL = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("Blocked by Safe Mode", isPresented: isPresented) {
                Button("OK", role: .cancel) { blockedSQL = nil }
            } message: {
                Text("Safe Mode is enabled. DDL statements (DROP, etc.) are blocked to protect your data.\n\nDisable Safe Mode from the toolbar to run this query.")
            }
    }
}

extension View {
    /// Attach the Safe-Mode-blocked alert to any view.
    func safeModeBlocked(sql: Binding<String?>) -> some View {
        modifier(SafeModeBlockedModifier(blockedSQL: sql))
    }
}
