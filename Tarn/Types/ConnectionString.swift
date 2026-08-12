//
//  ConnectionString.swift
//  Tarn
//
//  Created by ghazi
//

import Foundation

/// Represents a parsed PostgreSQL connection string
struct ConnectionString {
    let scheme: String
    let username: String?
    let password: String?
    let host: String
    let port: Int
    let database: String?
    let queryParameters: [String: String]
    let sslMode: SSLMode

    /// Returns a list of query parameters that are not currently supported by the application
    var unsupportedParameters: [String] {
        let unsupported = [
            "connect_timeout", "application_name",
            "client_encoding", "options", "fallback_application_name",
            "keepalives", "keepalives_idle", "keepalives_interval",
            "keepalives_count", "tcp_user_timeout", "replication",
            "gssencmode", "sslcert", "sslkey", "sslrootcert",
            "sslcrl", "requirepeer", "ssl_min_protocol_version",
            "ssl_max_protocol_version", "krbsrvname", "gsslib",
            "service", "target_session_attrs"
        ]

        return queryParameters.keys.filter { unsupported.contains($0) }
    }
}
