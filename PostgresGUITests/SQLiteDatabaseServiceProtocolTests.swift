//
//  SQLiteDatabaseServiceProtocolTests.swift
//  PostgresGUITests
//
//  Verifies that SQLiteDatabaseService correctly conforms to DatabaseServiceProtocol
//  and that stub/delegating methods behave as documented.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("SQLiteDatabaseService + DatabaseServiceProtocol")
struct SQLiteDatabaseServiceProtocolTests {

    // MARK: - Compile-time conformance

    @MainActor
    @Test func conformsToDatabaseServiceProtocol() async throws {
        // If SQLiteDatabaseService does not conform, this line would fail to compile.
        let service: DatabaseServiceProtocol = SQLiteDatabaseService()
        _ = service.isConnected
    }

    // MARK: - Stub methods that must throw .notSupported

    @MainActor
    @Test func connectPostgresThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.connect(
                host: "localhost",
                port: 5432,
                username: "user",
                password: "pass",
                database: "db",
                sslMode: .prefer
            )
        }
    }

    @MainActor
    @Test func createDatabaseThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.createDatabase(name: "test")
        }
    }

    @MainActor
    @Test func deleteDatabaseThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.deleteDatabase(name: "test")
        }
    }

    @MainActor
    @Test func deleteTableThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.deleteTable(schema: "main", table: "foo")
        }
    }

    @MainActor
    @Test func truncateTableThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.truncateTable(schema: "main", table: "foo")
        }
    }

    @MainActor
    @Test func deleteRowsThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.deleteRows(
                schema: "main",
                table: "foo",
                primaryKeyColumns: ["id"],
                rows: []
            )
        }
    }

    @MainActor
    @Test func updateRowThrowsNotSupported() async {
        let service = SQLiteDatabaseService()
        await #expect(throws: FileOpenError.notSupported) {
            try await service.updateRow(
                schema: "main",
                table: "foo",
                primaryKeyColumns: ["id"],
                originalRow: TableRow(values: [:]),
                updatedValues: [:]
            )
        }
    }

    // MARK: - Stub methods that return fixed values without connecting

    @MainActor
    @Test func fetchDatabasesReturnsEmptyList() async throws {
        let service = SQLiteDatabaseService()
        let result = try await service.fetchDatabases()
        #expect(result.isEmpty)
    }

    @MainActor
    @Test func fetchSchemasReturnsMain() async throws {
        let service = SQLiteDatabaseService()
        let result = try await service.fetchSchemas(database: "anything")
        #expect(result == ["main"])
    }

    // MARK: - State before connection

    @MainActor
    @Test func initiallyNotConnected() {
        let service = SQLiteDatabaseService()
        #expect(service.isConnected == false)
    }

    @MainActor
    @Test func connectedDatabaseIsNilBeforeConnect() {
        let service = SQLiteDatabaseService()
        #expect(service.connectedDatabase == nil)
    }
}
