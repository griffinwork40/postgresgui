//
//  HealthInspectorViewModel.swift
//  PostgresGUI
//
//  ViewModel for the Database Health Inspector sheet.
//  Loads health data from the service and drives maintenance actions.
//

import Foundation
import SwiftUI

// MARK: - HealthInspectorViewModel

@MainActor
@Observable
final class HealthInspectorViewModel {

    // MARK: - State

    enum LoadState {
        case idle
        case loading
        case loaded(DatabaseHealth)
        case failed(String)
    }

    enum ActionState {
        case idle
        case running(String)
        case succeeded(String)
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var actionState: ActionState = .idle
    private(set) var lastIntegrityResult: IntegrityCheckResult?

    // MARK: - Dependencies

    private let service: SQLiteDatabaseService

    init(service: SQLiteDatabaseService) {
        self.service = service
    }

    // MARK: - Load

    func refresh() async {
        loadState = .loading
        do {
            let health = try await service.fetchDatabaseHealth()
            loadState = .loaded(health)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Maintenance Actions

    func runIntegrityCheck() async {
        actionState = .running("Running integrity check…")
        do {
            let result = try await service.runIntegrityCheck()
            lastIntegrityResult = result
            if result.isOK {
                actionState = .succeeded("Integrity check passed ✓")
            } else {
                actionState = .failed("Integrity check found \(result.messages.count) issue(s)")
            }
        } catch {
            actionState = .failed("Integrity check failed: \(error.localizedDescription)")
        }
    }

    func runVacuum() async {
        actionState = .running("Running VACUUM…")
        do {
            try await service.runVacuum()
            actionState = .succeeded("VACUUM completed")
            // Refresh metrics after compaction
            await refresh()
        } catch {
            actionState = .failed("VACUUM failed: \(error.localizedDescription)")
        }
    }

    func runAnalyze() async {
        actionState = .running("Running ANALYZE…")
        do {
            try await service.runAnalyze()
            actionState = .succeeded("ANALYZE completed")
        } catch {
            actionState = .failed("ANALYZE failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatters

    func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func formattedMmapSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Disabled" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    func formattedFragmentation(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    func formattedDuration(_ interval: TimeInterval) -> String {
        String(format: "%.2fs", interval)
    }
}
