//
//  RootView.swift
//  Tarn
//
//  App entry point. Delegates business logic to RootViewModel.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appState = AppState()
    @State private var loadingState = LoadingState()
    @State private var tabManager = TabManager()
    @State private var viewModel: RootViewModel?
    @State private var tabChangeTask: Task<Void, Never>?
    @Query private var connections: [ConnectionProfile]
    @Query private var fileProfiles: [DatabaseFileProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.keychainService) private var keychainService

    var body: some View {
        ZStack {
            Group {
                if shouldShowWelcomeScreen(
                    connectionCount: connections.count,
                    fileProfileCount: fileProfiles.count
                ) {
                    WelcomeView()
                        .environment(appState)
                } else {
                    MainSplitView()
                        .environment(appState)
                }
            }

            if loadingState.isLoading {
                LoadingOverlayView(phase: loadingState.phase)
            }
        }
        .environment(tabManager)
        .environment(loadingState)
        // NOTE: ConnectionFormView sheet removed — this is a SQLite-only app.
        //       The Postgres connection form (ConnectionFormView/ConnectionFormViewModel) was deleted.
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingCreateDatabase },
            set: { appState.navigation.isShowingCreateDatabase = $0 }
        )) {
            CreateDatabaseView { database in
                Task {
                    await viewModel?.selectDatabase(database)
                }
            }
            .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingFileOpen },
            set: { appState.navigation.isShowingFileOpen = $0 }
        )) {
            FileOpenView { profile in
                Task {
                    await viewModel?.connectSQLiteFile(profile: profile)
                }
            }
            .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingDiscovery },
            set: { appState.navigation.isShowingDiscovery = $0 }
        )) {
            DatabaseDiscoveryView { url in
                Task { @MainActor in
                    guard let vm = viewModel else { return }
                    let profile = openDiscoveredDatabase(url: url, modelContext: modelContext)
                    await vm.connectSQLiteFile(profile: profile)
                }
            }
        }
        .task {
            // Wire up tabManager to appState for result caching
            appState.tabManager = tabManager

            // Create ViewModel with dependencies
            let vm = RootViewModel(
                appState: appState,
                tabManager: tabManager,
                loadingState: loadingState,
                modelContext: modelContext,
                keychainService: keychainService
            )
            viewModel = vm
            await vm.initializeApp(connections: connections)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { notification in
            tabChangeTask?.cancel()
            tabChangeTask = Task {
                // Now expects TabViewModel instead of TabState
                await viewModel?.handleTabChange(
                    notification.object as? TabViewModel,
                    connections: connections
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTab)) { _ in
            viewModel?.saveCurrentStateToTab()
            tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
            if let newTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await viewModel?.handleTabChange(newTab, connections: connections)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            viewModel?.closeCurrentTab()
            if let newActiveTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await viewModel?.handleTabChange(newActiveTab, connections: connections)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDiscovery)) { _ in
            appState.navigation.isShowingDiscovery = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            appState.navigation.isShowingKeyboardShortcuts = true
        }
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingKeyboardShortcuts },
            set: { appState.navigation.isShowingKeyboardShortcuts = $0 }
        )) {
            KeyboardShortcutsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            appState.navigation.isShowingHelp = true
        }
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingHelp },
            set: { appState.navigation.isShowingHelp = $0 }
        )) {
            HelpView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                Task { @MainActor in
                    viewModel?.saveCurrentStateToTab()
                    await appState.cleanupOnWindowClose()
                }
            }
        }
        .alert("Connection Error", isPresented: .init(
            get: { viewModel?.initializationError != nil },
            set: { if !$0 { viewModel?.initializationError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel?.initializationError = nil }
        } message: {
            if let error = viewModel?.initializationError { Text(error) }
        }
    }
}

// MARK: - Helpers

/// Fetch or create a DatabaseFileProfile for a discovered file URL, then mark it as opened.
@MainActor
private func openDiscoveredDatabase(url: URL, modelContext: ModelContext) -> DatabaseFileProfile {
    let filePath = url.path
    let name = url.deletingPathExtension().lastPathComponent
    let descriptor = FetchDescriptor<DatabaseFileProfile>(
        predicate: #Predicate { $0.filePath == filePath }
    )
    let profile: DatabaseFileProfile
    if let existing = (try? modelContext.fetch(descriptor))?.first {
        profile = existing
    } else {
        profile = DatabaseFileProfile(name: name, filePath: filePath)
        modelContext.insert(profile)
    }
    profile.lastOpenedAt = Date()
    profile.updatedAt = Date()
    try? modelContext.save()
    return profile
}
