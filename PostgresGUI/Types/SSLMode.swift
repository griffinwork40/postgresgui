//
//  SSLMode.swift
//  PostgresGUI
//
//  Created by ghazi
//

import Foundation

/// SSL mode options for PostgreSQL connections
enum SSLMode: String, Sendable, CaseIterable {
    case disable = "disable"
    case allow = "allow"
    case prefer = "prefer"
    case require = "require"
    case verifyCA = "verify-ca"
    case verifyFull = "verify-full"

    /// Default SSL mode when not specified
    /// Using 'disable' as default for better localhost compatibility
    nonisolated static let `default` = SSLMode.disable

    /// Returns appropriate SSL mode for a given host
    /// Remote hosts require SSL; local hosts disable it
    nonisolated static func defaultFor(host: String) -> SSLMode {
        let h = host.lowercased()
        let isLocal = h.isEmpty || h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local")
        return isLocal ? .disable : .require
    }

    nonisolated var displayName: String {
        switch self {
        case .disable:
            return "Disable"
        case .allow:
            return "Allow"
        case .prefer:
            return "Prefer"
        case .require:
            return "Require"
        case .verifyCA:
            return "Verify CA"
        case .verifyFull:
            return "Verify Full"
        }
    }
}
