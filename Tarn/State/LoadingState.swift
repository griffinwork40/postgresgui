//
//  LoadingState.swift
//  Tarn
//
//  Created by ghazi on 12/20/25.
//

import SwiftUI

enum LoadingPhase: String {
    case initializingApp = "Initializing..."
    case restoringTabs = "Restoring tabs..."
    case connectingToDatabase = "Connecting to database..."
    case loadingDatabases = "Loading databases..."
    case loadingTables = "Loading tables..."
    case ready = ""
}

@Observable
@MainActor
class LoadingState {
    var phase: LoadingPhase = .initializingApp

    /// Set to true once initial app loading is complete
    var hasCompletedInitialLoad: Bool = false

    var isLoading: Bool {
        phase != .ready
    }

    var message: String {
        phase.rawValue
    }

    func setPhase(_ phase: LoadingPhase) {
        self.phase = phase
    }

    func setReady() {
        self.phase = .ready
        self.hasCompletedInitialLoad = true
    }
}
