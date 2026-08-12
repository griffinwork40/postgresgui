//
//  UserDefaultsProtocol.swift
//  Tarn
//
//  Protocol abstraction for UserDefaults operations
//  Enables dependency injection and testability
//

import Foundation

/// Protocol for UserDefaults operations
/// Allows injecting a mock implementation for testing
protocol UserDefaultsProtocol {
    /// Get a string value for a key
    func string(forKey key: String) -> String?

    /// Set a value for a key
    func set(_ value: Any?, forKey key: String)

    /// Remove a value for a key
    func removeObject(forKey key: String)
}

/// Wrapper for standard UserDefaults
@MainActor
class UserDefaultsWrapper: UserDefaultsProtocol {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
