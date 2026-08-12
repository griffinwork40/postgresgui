//
//  DatabaseDiscoveryViewModel.swift
//  PostgresGUI
//
//  ViewModel for DatabaseDiscoveryView. Drives directory scanning
//  via DatabaseDiscoveryService and exposes scan state to SwiftUI.
//

import Foundation
import Observation

@Observable
@MainActor
final class DatabaseDiscoveryViewModel {

    // MARK: - Published State

    var discoveredDatabases: [DiscoveredDatabase] = []
    var isScanning: Bool = false
    var filesScanned: Int = 0
    var errorMessage: String?
    var selectedDatabase: DiscoveredDatabase?

    // MARK: - Private

    private let service = DatabaseDiscoveryService()
    private var scanTask: Task<Void, Never>?

    // MARK: - Actions

    /// Begin scanning `directory`. Cancels any in-progress scan first.
    func startScan(directory: URL) {
        cancelScan()
        discoveredDatabases = []
        filesScanned = 0
        errorMessage = nil
        selectedDatabase = nil
        isScanning = true

        scanTask = Task {
            defer { Task { @MainActor in self.isScanning = false } }
            do {
                let results = try await service.scan(directory: directory) { count in
                    Task { @MainActor in self.filesScanned = count }
                }
                await MainActor.run {
                    self.discoveredDatabases = results.sorted {
                        $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
                    }
                    self.filesScanned = results.count
                }
            } catch is CancellationError {
                // User cancelled — clear results silently
                await MainActor.run { self.discoveredDatabases = [] }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Cancel an in-progress scan.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}
