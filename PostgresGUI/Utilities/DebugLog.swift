//
//  DebugLog.swift
//  PostgresGUI
//
//  Conditional logging utility that only logs in Debug builds
//

import Foundation

/// Utility for conditional debug logging
/// All logs are suppressed in Release builds for performance and privacy
enum DebugLog {
    /// Print a message only in Debug builds
    /// - Parameter items: Items to print (same signature as Swift's print)
    nonisolated static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
        #endif
    }
}
