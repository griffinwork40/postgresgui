//
//  TarnApp.swift
//  Tarn
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct TarnApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try TarnModelContainerFactory.makeModelContainer()
        } catch {
            // Critical errors should remain visible in Release builds
            Swift.print("⚠️ Failed to create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer. Existing user data was left untouched: \(error)")
        }
    }()

    var body: some Scene {
        Window("Tarn", id: "main") {
            RootView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(action: openNewTab) {
                    Text("New Tab")
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(action: closeCurrentTab) {
                    Text("Close Tab")
                }
                .keyboardShortcut("w", modifiers: [.command])

                Divider()

                Button(action: showDiscoverDatabases) {
                    Label("Discover Databases…", systemImage: "folder.badge.magnifyingglass")
                }
            }

            CommandGroup(after: .appInfo) {
                Button(action: {
                    if let url = URL(string: "https://tarn.com/support") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Help and Support...", systemImage: "questionmark.circle")
                }

                Button(action: {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }) {
                    Label("Keyboard Shortcuts...", systemImage: "keyboard")
                }
            }

            CommandGroup(replacing: .help) {
                Button(action: {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }) {
                    Text("Tarn Help")
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    // Menu commands can't access TabManager directly, so we use notifications.
    // RootView observes these and calls tabManager methods.
    private func openNewTab() {
        NotificationCenter.default.post(name: .createNewTab, object: nil)
    }
    private func closeCurrentTab() {
        NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
    }
    private func showDiscoverDatabases() {
        NotificationCenter.default.post(name: .showDiscovery, object: nil)
    }
}

extension Notification.Name {
    static let createNewTab = Notification.Name("createNewTab")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showHelp = Notification.Name("showHelp")
    static let showDiscovery = Notification.Name("showDiscovery")
    static let runQueryAfterConfirmation = Notification.Name("runQueryAfterConfirmation")
    static let openDroppedSQLiteFile = Notification.Name("openDroppedSQLiteFile")
}
