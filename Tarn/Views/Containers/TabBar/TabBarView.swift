//
//  TabBarView.swift
//  Tarn
//
//  Created by ghazi on 12/20/25.
//

import SwiftUI
import SwiftData

struct TabBarView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(AppState.self) private var appState
    @Query private var connections: [ConnectionProfile]
    @Query private var savedQueries: [SavedQuery]

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabManager.tabs) { tab in
                            TabItemView(
                                tab: tab,
                                isActive: tab.id == tabManager.activeTab?.id,
                                connectionName: connectionName(for: tab),
                                onSelect: { selectTab(tab) },
                                onClose: { closeTab(tab) }
                            )
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: tabManager.activeTab?.id) { _, newId in
                    if let newId = newId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .trailing)
                        }
                    }
                }
            }

            Spacer()

            Button(action: addNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
        // .overlay(alignment: .top) { // ghazi 12/24/25 - remove the top divider
        //     Divider()
        // }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func connectionName(for tab: TabViewModel) -> String {
        // Check if tab is pending deletion
        guard !tab.isPendingDeletion else {
            return "Closing..."
        }

        // If tab has a saved query, show "db / query_name"
        if let savedQueryId = tab.savedQueryId,
           let savedQuery = savedQueries.first(where: { $0.id == savedQueryId }) {
            if let dbName = tab.databaseName {
                return "\(dbName) / \(savedQuery.name)"
            }
            return savedQuery.name
        }

        // Otherwise show connection / database
        if let connectionId = tab.connectionId,
           let connection = connections.first(where: { $0.id == connectionId }) {
            if let dbName = tab.databaseName {
                return "\(connection.displayName) / \(dbName)"
            }
            return connection.displayName
        }
        return "New Tab \(tab.order + 1)"
    }

    private func selectTab(_ tab: TabViewModel) {
        guard !tab.isPendingDeletion else { return }
        guard tab.id != tabManager.activeTab?.id else { return }

        // Save only query state before switching - don't save connection/database
        // as those are already stored in the tab and should only be updated
        // when the user explicitly changes them (not during rapid tab switching)
        if let activeTab = tabManager.activeTab, !activeTab.isPendingDeletion {
            tabManager.updateActiveTab(
                connectionId: activeTab.connectionId,
                databaseName: activeTab.databaseName,
                queryText: appState.query.queryText,
                savedQueryId: appState.query.currentSavedQueryId
            )
        }

        // Switch to new tab
        tabManager.switchToTab(tab)

        // Notify that tab changed - the view will need to reload
        NotificationCenter.default.post(name: .tabDidChange, object: tab)
    }

    private func closeTab(_ tab: TabViewModel) {
        guard !tab.isPendingDeletion else { return }

        let wasActive = tab.id == tabManager.activeTab?.id
        tabManager.closeTab(tab)

        // If we closed the active tab, notify to reload with the new active tab
        if wasActive, let newActiveTab = tabManager.activeTab {
            NotificationCenter.default.post(name: .tabDidChange, object: newActiveTab)
        }
    }

    private func addNewTab() {
        tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
        NotificationCenter.default.post(name: .tabDidChange, object: tabManager.activeTab)
    }
}

struct TabItemView: View {
    let tab: TabViewModel
    let isActive: Bool
    let connectionName: String
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(connectionName)
                .font(.system(size: Constants.FontSize.small))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isActive ? .primary : .secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
        }
        .frame(maxWidth: 180)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.secondary.opacity(0.3) : (isHovered ? Color.secondary.opacity(0.15) : Color.clear))
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

extension Notification.Name {
    static let tabDidChange = Notification.Name("tabDidChange")
}
