//
//  ConnectionStringParserTests.swift
//  TarnTests
//
//  Unit tests for ConnectionStringParser.
//

import Foundation
import Testing
@testable import Tarn

// MARK: - Parse Tests

@Suite("ConnectionStringParser.parse")
struct ConnectionStringParserParseTests {

    @Suite("Valid Connection Strings")
    struct ValidConnectionStrings {

        @Test func parsesMinimalConnectionString() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost")
            #expect(result.scheme == "postgresql")
            #expect(result.host == "localhost")
            #expect(result.port == 5432)
            #expect(result.username == nil)
            #expect(result.password == nil)
            #expect(result.database == nil)
        }

        @Test func parsesPostgresScheme() throws {
            let result = try ConnectionStringParser.parse("postgres://localhost")
            #expect(result.scheme == "postgres")
            #expect(result.host == "localhost")
        }

        @Test func parsesPostgresqlScheme() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost")
            #expect(result.scheme == "postgresql")
        }

        @Test func parsesHostAndPort() throws {
            let result = try ConnectionStringParser.parse("postgresql://myserver.com:5433")
            #expect(result.host == "myserver.com")
            #expect(result.port == 5433)
        }

        @Test func parsesUsernameAndPassword() throws {
            let result = try ConnectionStringParser.parse("postgresql://user:pass@localhost")
            #expect(result.username == "user")
            #expect(result.password == "pass")
            #expect(result.host == "localhost")
        }

        @Test func parsesUsernameOnly() throws {
            let result = try ConnectionStringParser.parse("postgresql://admin@localhost")
            #expect(result.username == "admin")
            #expect(result.password == nil)
        }

        @Test func parsesDatabaseName() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost/mydb")
            #expect(result.database == "mydb")
        }

        @Test func parsesFullConnectionString() throws {
            let result = try ConnectionStringParser.parse("postgresql://user:secret@db.example.com:5433/production")
            #expect(result.scheme == "postgresql")
            #expect(result.username == "user")
            #expect(result.password == "secret")
            #expect(result.host == "db.example.com")
            #expect(result.port == 5433)
            #expect(result.database == "production")
        }

        @Test func parsesIPv4Host() throws {
            let result = try ConnectionStringParser.parse("postgresql://192.168.1.100:5432/testdb")
            #expect(result.host == "192.168.1.100")
            #expect(result.port == 5432)
            #expect(result.database == "testdb")
        }

        @Test func parsesWithQueryParameters() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost/mydb?sslmode=require&application_name=test")
            #expect(result.database == "mydb")
            #expect(result.queryParameters["sslmode"] == "require")
            #expect(result.queryParameters["application_name"] == "test")
        }

        @Test func parsesSSLModeFromQuery() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost?sslmode=require")
            #expect(result.sslMode == .require)
        }

        @Test func parsesSSLModeVerifyFull() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost?sslmode=verify-full")
            #expect(result.sslMode == .verifyFull)
        }

        @Test func defaultsSSLModeWhenNotSpecified() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost")
            #expect(result.sslMode == .default)
        }

        @Test func defaultsSSLModeForUnknownValue() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost?sslmode=unknown")
            #expect(result.sslMode == .default)
        }

        @Test func trimsWhitespace() throws {
            let result = try ConnectionStringParser.parse("  postgresql://localhost  ")
            #expect(result.host == "localhost")
        }

        @Test func handlesPercentEncodedPassword() throws {
            let result = try ConnectionStringParser.parse("postgresql://user:p%40ssword@localhost")
            #expect(result.password == "p@ssword")
        }

        @Test func handlesPercentEncodedUsername() throws {
            let result = try ConnectionStringParser.parse("postgresql://user%40domain:pass@localhost")
            #expect(result.username == "user@domain")
        }
    }

    @Suite("Invalid Connection Strings")
    struct InvalidConnectionStrings {

        @Test func throwsOnEmptyString() {
            #expect(throws: ConnectionStringParser.ParseError.invalidFormat) {
                _ = try ConnectionStringParser.parse("")
            }
        }

        @Test func throwsOnWhitespaceOnly() {
            #expect(throws: ConnectionStringParser.ParseError.invalidFormat) {
                _ = try ConnectionStringParser.parse("   ")
            }
        }

        @Test func throwsOnInvalidScheme() {
            #expect(throws: ConnectionStringParser.ParseError.invalidScheme) {
                _ = try ConnectionStringParser.parse("mysql://localhost")
            }
        }

        @Test func throwsOnMissingScheme() {
            #expect(throws: ConnectionStringParser.ParseError.invalidScheme) {
                _ = try ConnectionStringParser.parse("localhost:5432")
            }
        }

        @Test func throwsOnEmptyHost() {
            #expect(throws: ConnectionStringParser.ParseError.emptyHost) {
                _ = try ConnectionStringParser.parse("postgresql:///mydb")
            }
        }

        @Test func throwsOnInvalidPort() {
            #expect(throws: ConnectionStringParser.ParseError.invalidPort) {
                _ = try ConnectionStringParser.parse("postgresql://localhost:99999")
            }
        }

        @Test func throwsOnZeroPort() {
            #expect(throws: ConnectionStringParser.ParseError.invalidPort) {
                _ = try ConnectionStringParser.parse("postgresql://localhost:0")
            }
        }

        @Test func throwsOnNegativePort() {
            // Negative port results in malformed URL (URLComponents returns nil)
            #expect(throws: ConnectionStringParser.ParseError.malformedURL) {
                _ = try ConnectionStringParser.parse("postgresql://localhost:-1")
            }
        }
    }

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func handlesTrailingSlash() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost/")
            #expect(result.host == "localhost")
            #expect(result.database == nil)
        }

        @Test func handlesEmptyQueryValue() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost?sslmode=")
            #expect(result.queryParameters["sslmode"] == "")
        }

        @Test func handlesMultipleQueryParams() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost?a=1&b=2&c=3")
            #expect(result.queryParameters.count == 3)
            #expect(result.queryParameters["a"] == "1")
            #expect(result.queryParameters["b"] == "2")
            #expect(result.queryParameters["c"] == "3")
        }

        @Test func parsesMaxValidPort() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost:65535")
            #expect(result.port == 65535)
        }

        @Test func parsesMinValidPort() throws {
            let result = try ConnectionStringParser.parse("postgresql://localhost:1")
            #expect(result.port == 1)
        }
    }
}

// MARK: - Build Tests

@Suite("ConnectionStringParser.build")
struct ConnectionStringParserBuildTests {

    @Test func buildsMinimalConnectionString() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(result == "postgresql://localhost")
    }

    @Test func includesNonDefaultPort() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5433,
            database: nil
        )
        #expect(result == "postgresql://localhost:5433")
    }

    @Test func omitsDefaultPort() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(!result.contains(":5432"))
    }

    @Test func includesUsername() {
        let result = ConnectionStringParser.build(
            username: "admin",
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(result == "postgresql://admin@localhost")
    }

    @Test func includesUsernameAndPassword() {
        let result = ConnectionStringParser.build(
            username: "admin",
            password: "secret",
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(result == "postgresql://admin:secret@localhost")
    }

    @Test func includesDatabase() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: "mydb"
        )
        #expect(result == "postgresql://localhost/mydb")
    }

    @Test func includesSSLMode() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil,
            sslMode: .require
        )
        #expect(result.contains("sslmode=require"))
    }

    @Test func omitsDefaultSSLMode() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil,
            sslMode: .default
        )
        #expect(!result.contains("sslmode"))
    }

    @Test func buildsFullConnectionString() {
        let result = ConnectionStringParser.build(
            username: "user",
            password: "pass",
            host: "db.example.com",
            port: 5433,
            database: "production",
            sslMode: .require
        )
        #expect(result.contains("postgresql://"))
        #expect(result.contains("user:pass@"))
        #expect(result.contains("db.example.com"))
        #expect(result.contains(":5433"))
        #expect(result.contains("/production"))
        #expect(result.contains("sslmode=require"))
    }

    @Test func ignoresEmptyUsername() {
        let result = ConnectionStringParser.build(
            username: "",
            password: nil,
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(result == "postgresql://localhost")
    }

    @Test func ignoresEmptyPassword() {
        let result = ConnectionStringParser.build(
            username: "admin",
            password: "",
            host: "localhost",
            port: 5432,
            database: nil
        )
        #expect(result == "postgresql://admin@localhost")
    }

    @Test func ignoresEmptyDatabase() {
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: "localhost",
            port: 5432,
            database: ""
        )
        #expect(result == "postgresql://localhost")
    }
}

// MARK: - Parse Error Tests

@Suite("ConnectionStringParser.ParseError")
struct ParseErrorTests {

    @Test func invalidFormatHasDescription() {
        let error = ConnectionStringParser.ParseError.invalidFormat
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func invalidSchemeHasDescription() {
        let error = ConnectionStringParser.ParseError.invalidScheme
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func invalidPortHasDescription() {
        let error = ConnectionStringParser.ParseError.invalidPort
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func emptyHostHasDescription() {
        let error = ConnectionStringParser.ParseError.emptyHost
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func malformedURLHasDescription() {
        let error = ConnectionStringParser.ParseError.malformedURL
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func invalidPercentEncodingHasDescription() {
        let error = ConnectionStringParser.ParseError.invalidPercentEncoding
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }
}

// MARK: - Roundtrip Tests

@Suite("ConnectionStringParser Roundtrip")
struct RoundtripTests {

    @Test func roundtripPreservesComponents() throws {
        let original = "postgresql://user:pass@localhost:5433/mydb?sslmode=require"
        let parsed = try ConnectionStringParser.parse(original)
        let rebuilt = ConnectionStringParser.build(
            username: parsed.username,
            password: parsed.password,
            host: parsed.host,
            port: parsed.port,
            database: parsed.database,
            sslMode: parsed.sslMode
        )
        let reparsed = try ConnectionStringParser.parse(rebuilt)

        #expect(reparsed.username == parsed.username)
        #expect(reparsed.password == parsed.password)
        #expect(reparsed.host == parsed.host)
        #expect(reparsed.port == parsed.port)
        #expect(reparsed.database == parsed.database)
        #expect(reparsed.sslMode == parsed.sslMode)
    }
}
