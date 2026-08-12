//
//  ClockProtocol.swift
//  Tarn
//
//  Protocol abstraction for time operations
//  Enables controllable time in tests
//

import Foundation

/// Protocol for time operations
/// Allows injecting a mock clock for deterministic testing
protocol ClockProtocol {
    /// Get the current date and time
    func now() -> Date
}

/// System clock implementation using real time
@MainActor
class SystemClock: ClockProtocol {
    init() {}

    func now() -> Date {
        Date()
    }
}
