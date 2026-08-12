//
//  SidebarModifiers.swift
//  Tarn
//
//  ViewModifier structs and button style extracted from ConnectionsDatabasesSidebar.
//

import SwiftUI

// MARK: - Button Style

struct RefreshToolbarButtonStyle: ButtonStyle {
    let isActive: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Capsule()
                    .fill(backgroundColor(isPressed: configuration.isPressed))
                    .frame(width: 28, height: 26)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.secondary.opacity(0.28)
        }
        if isActive {
            return Color.secondary.opacity(0.18)
        }
        if isHovered {
            return Color.secondary.opacity(0.12)
        }
        return Color.clear
    }
}

// MARK: - View Modifiers

// TODO(sqlite): DatabaseAlertsModifier contains a "Delete Database" confirmation dialog that is
// Postgres-only dead code. SQLite has no concept of dropping databases, and `databaseToDelete`
// is never set for SQLite connections, so the dialog never appears. Leave in place for now;
// remove when the Postgres connection path is fully retired.
struct DatabaseAlertsModifier: ViewModifier {
    @Binding var showConnectionError: Bool
    @Binding var connectionError: String?
    @Binding var databaseToDelete: DatabaseInfo?
    @Binding var deleteError: String?
    let deleteDatabase: (DatabaseInfo) async -> Void

    func body(content: Content) -> some View {
        content
            .alert("Connection Failed", isPresented: $showConnectionError) {
                Button("OK", role: .cancel) {
                    connectionError = nil
                }
            } message: {
                if let error = connectionError {
                    Text(error)
                }
            }
            .confirmationDialog(
                "Delete Database?",
                isPresented: Binding(
                    get: { databaseToDelete != nil },
                    set: { if !$0 { databaseToDelete = nil } }
                ),
                presenting: databaseToDelete
            ) { database in
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteDatabase(database)
                    }
                }
                Button("Cancel", role: .cancel) {
                    databaseToDelete = nil
                }
            } message: { database in
                Text("Are you sure you want to delete '\(database.name)'? This action cannot be undone.")
            }
            .alert("Error Deleting Database", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    deleteError = nil
                }
            } message: {
                if let error = deleteError {
                    Text(error)
                }
            }
    }
}

struct ConnectionAlertsModifier: ViewModifier {
    @Binding var connectionToDelete: ConnectionProfile?
    let deleteConnection: (ConnectionProfile) async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Connection?",
                isPresented: Binding(
                    get: { connectionToDelete != nil },
                    set: { if !$0 { connectionToDelete = nil } }
                ),
                presenting: connectionToDelete
            ) { connection in
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteConnection(connection)
                    }
                }
                Button("Cancel", role: .cancel) {
                    connectionToDelete = nil
                }
            } message: { connection in
                Text("Are you sure you want to delete '\(connection.displayName)'? This action cannot be undone.")
            }
    }
}

struct TableLoadingTimeoutAlertModifier: ViewModifier {
    let appState: AppState
    let retryAction: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Loading Tables Timed Out", isPresented: Binding(
                get: { appState.connection.showTableLoadingTimeoutAlert },
                set: { appState.connection.showTableLoadingTimeoutAlert = $0 }
            )) {
                Button("Try Again") {
                    appState.connection.showTableLoadingTimeoutAlert = false
                    appState.connection.tableLoadingError = nil
                    retryAction()
                }
                Button("Cancel", role: .cancel) {
                    appState.connection.showTableLoadingTimeoutAlert = false
                }
            } message: {
                Text("Loading tables took longer than \(Int(Constants.Timeout.databaseOperation)) seconds. The database may be slow or unresponsive.")
            }
    }
}
