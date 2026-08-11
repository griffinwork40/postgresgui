//
//  ConnectionDropdown.swift
//  PostgresGUI
//
//  Created by ghazi on 12/30/25.
//

import SwiftUI

/// Font sizes used in the connection dropdown
private enum DropdownFontSize {
    static let label: CGFloat = Constants.FontSize.small
    static let chevron: CGFloat = 8
    static let dropdownItem: CGFloat = 12
    static let checkmark: CGFloat = Constants.FontSize.smallIcon
    static let actionIcon: CGFloat = Constants.FontSize.small
}

/// Dropdown for selecting and managing connections
struct ConnectionDropdown: View {
    @Environment(AppState.self) private var appState

    @Binding var isOpen: Bool
    let connections: [ConnectionProfile]
    let onSelect: (ConnectionProfile) -> Void
    let onEdit: (ConnectionProfile) -> Void
    let onDelete: (ConnectionProfile) -> Void
    let onCreate: () -> Void

    private var hasConnection: Bool {
        appState.connection.activeConnection != nil
    }

    private var connectionDisplayName: String {
        switch appState.connection.activeConnection {
        case .postgres(let p): return p.displayName
        case .sqlite(let p): return p.displayName
        case nil: return "Select Connection"
        }
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            if !hasConnection {
                PhaseAnimator([0.4, 1.0]) { phase in
                    buttonContent(opacity: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            } else {
                buttonContent(opacity: 1.0)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdownContent
        }
    }

    // MARK: - Button Content

    private func buttonContent(opacity: Double) -> some View {
        HStack(spacing: 6) {
            if hasConnection {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Text("⚠️")
                    .font(.system(size: 12))
            }
            Text(connectionDisplayName)
                .font(.system(size: DropdownFontSize.label))
                .foregroundColor(hasConnection ? .primary : .secondary)
                .opacity(opacity)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: DropdownFontSize.chevron))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Dropdown Content

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if connections.isEmpty {
                Text("No connections")
                    .font(.system(size: DropdownFontSize.dropdownItem))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(connections.sorted { $0.displayName < $1.displayName }) { connection in
                            connectionRow(connection)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.vertical, 4)

            newConnectionButton
        }
        .padding(.vertical, 8)
        .frame(minWidth: 200)
    }

    // MARK: - Connection Row

    @ViewBuilder
    private func connectionRow(_ connection: ConnectionProfile) -> some View {
        let isActive = appState.connection.currentConnection?.id == connection.id

        HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark" : "")
                .font(.system(size: DropdownFontSize.checkmark, weight: .semibold))
                .frame(width: 12)
                .foregroundColor(.accentColor)

            Text(connection.displayName)
                .font(.system(size: DropdownFontSize.dropdownItem))
                .frame(maxWidth: 200, alignment: .leading)
                .lineLimit(1)

            Button {
                isOpen = false
                onEdit(connection)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: DropdownFontSize.actionIcon))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit connection")

            Button {
                isOpen = false
                onDelete(connection)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: DropdownFontSize.actionIcon))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete connection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                onSelect(connection)
                isOpen = false
            }
        }
    }

    // MARK: - New Connection Button

    private var newConnectionButton: some View {
        Button {
            isOpen = false
            onCreate()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: DropdownFontSize.dropdownItem))
                Text("New Connection")
                    .font(.system(size: DropdownFontSize.dropdownItem))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
