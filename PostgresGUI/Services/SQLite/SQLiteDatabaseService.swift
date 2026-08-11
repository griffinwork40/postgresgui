//
//  SQLiteDatabaseService.swift
//  PostgresGUI
//
//  High-level service facade for SQLite database operations.
//  Bridges between the SQLite service layer (typed results) and the
//  existing app state/UI layer (which still uses TableRow/QueryResult).
//
//  This service owns the connection manager and query executor,
//  and provides both typed and legacy (display) result interfaces.
//

import Foundation
import GRDB

@MainActor
class SQLiteDatabaseService {
    private let connectionManager = SQLiteConnectionManager()
    private let queryExecutor = SQLiteQueryExecutor()

    // MARK: - Connection State

    private var _isConnected: Bool = false
    private var _currentFilePath: String?

    var isConnected: Bool { _isConnected }
    var currentFilePath: String? { _currentFilePath }

    /// The file name of the currently opened database (for display).
    var connectedDatabaseName: String? {
        guard let path = _currentFilePath else { return nil }
        return (path as NSString).lastPathComponent
    }

    // MARK: - Connection Management

    /// Open a SQLite database file.
    func connect(filePath: String, readOnly: Bool = false) async throws {
        DebugLog.print("Opening: \(filePath)")
        _isConnected = false
        _currentFilePath = nil

        try await connectionManager.connect(filePath: filePath, readOnly: readOnly)

        _currentFilePath = filePath
        _isConnected = true
        DebugLog.print("Connected to: \(filePath)")
    }

    /// Close the current database.
    func disconnect() async {
        DebugLog.print("Disconnecting")
        await connectionManager.disconnect()
        _currentFilePath = nil
        _isConnected = false
    }

    /// Full shutdown.
    func shutdown() async {
        await connectionManager.shutdown()
        _currentFilePath = nil
        _isConnected = false
    }

    /// Interrupt in-flight operations.
    func interruptInFlightOperations() async {
        await connectionManager.interruptInFlightOperationForSupersession()
    }

    // MARK: - Table Operations (return domain models)

    /// Fetch tables from the database.
    func fetchTables() async throws -> [TableInfo] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchTables(db: db)
        }
    }

    /// Fetch column info for a table.
    func fetchColumnInfo(table: String) async throws -> [ColumnInfo] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchColumns(db: db, table: table)
        }
    }

    /// Fetch primary key columns for a table.
    func fetchPrimaryKeys(table: String) async throws -> [String] {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchPrimaryKeys(db: db, table: table)
        }
    }

    /// Get the DDL for a table.
    func generateDDL(table: String) async throws -> String {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.generateDDL(db: db, table: table)
        }
    }

    // MARK: - Query Execution (Typed Results)

    /// Execute arbitrary SQL and return typed results.
    func executeQueryTyped(_ sql: String) async throws -> TypedQueryResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.executeQuery(db: db, sql: sql)
        }
    }

    /// Fetch a page of table data as typed results.
    func fetchTableDataTyped(
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> TypedQueryResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { [queryExecutor] db in
            try queryExecutor.fetchTableData(db: db, table: table, limit: limit, offset: offset)
        }
    }

    // MARK: - Legacy Display Interface (for existing UI compatibility)

    /// Execute SQL and return legacy display types for existing UI code.
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        let typed = try await executeQueryTyped(sql)
        if let error = typed.error { throw error }
        return (typed.toDisplayRows(), typed.columnNames)
    }

    /// Fetch table data as legacy display types.
    func fetchTableData(
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        let typed = try await fetchTableDataTyped(table: table, limit: limit, offset: offset)
        if let error = typed.error { throw error }
        return typed.toDisplayRows()
    }

    // MARK: - Database Health

    /// Fetch a comprehensive health snapshot using PRAGMAs.
    func fetchDatabaseHealth() async throws -> DatabaseHealth {
        guard _isConnected else { throw FileOpenError.notConnected }
        let filePath = _currentFilePath
        return try await connectionManager.withDatabase { db in
            try PragmaQueryService.fetchHealth(db: db, filePath: filePath)
        }
    }

    /// Run a full PRAGMA integrity_check. May be slow on large databases.
    func runIntegrityCheck() async throws -> IntegrityCheckResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { db in
            try PragmaQueryService.runIntegrityCheck(db: db)
        }
    }

    /// Run a PRAGMA quick_check (faster, less thorough than integrity_check).
    func runQuickCheck() async throws -> IntegrityCheckResult {
        guard _isConnected else { throw FileOpenError.notConnected }
        return try await connectionManager.withDatabase { db in
            try PragmaQueryService.runQuickCheck(db: db)
        }
    }

    /// Rebuild the database file, reclaiming free pages and defragmenting storage.
    func runVacuum() async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        try await connectionManager.withDatabaseWrite { db in
            try db.execute(sql: "VACUUM")
        }
    }

    /// Update query planner statistics for all tables.
    func runAnalyze() async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        try await connectionManager.withDatabaseWrite { db in
            try db.execute(sql: "ANALYZE")
        }
    }
}

// MARK: - DatabaseServiceProtocol Conformance

extension SQLiteDatabaseService: DatabaseServiceProtocol {

    var connectedDatabase: String? { connectedDatabaseName }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode
    ) async throws {
        throw FileOpenError.notSupported
    }

    func interruptInFlightTableBrowseLoadForSupersession() async {
        await interruptInFlightOperations()
    }

    func fetchDatabases() async throws -> [DatabaseInfo] { [] }

    func createDatabase(name: String) async throws { throw FileOpenError.notSupported }

    func deleteDatabase(name: String) async throws { throw FileOpenError.notSupported }

    func fetchTables(database: String) async throws -> [TableInfo] {
        return try await fetchTables()
    }

    func fetchSchemas(database: String) async throws -> [String] { ["main"] }

    func deleteTable(schema: String, table: String) async throws { throw FileOpenError.notSupported }

    func truncateTable(schema: String, table: String) async throws { throw FileOpenError.notSupported }

    func generateDDL(schema: String, table: String) async throws -> String {
        return try await generateDDL(table: table)
    }

    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) {
        let typed = try await fetchTableDataTyped(table: table, limit: Int.max, offset: 0)
        if let error = typed.error { throw error }
        return (typed.toDisplayRows(), typed.columnNames)
    }

    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        return try await executeQuery(sql)
    }

    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        let affected = try await connectionManager.withDatabaseWrite { db in
            try SQLiteRowOperations.deleteRows(
                db: db,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                rows: rows
            )
        }
        DebugLog.print("Deleted \(affected) rows from \(table)")
    }

    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        let affected = try await connectionManager.withDatabaseWrite { db in
            try SQLiteRowOperations.updateRow(
                db: db,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                originalRow: originalRow,
                updatedValues: updatedValues
            )
        }
        guard affected > 0 else {
            throw FileOpenError.unknownError(
                "No rows were updated. The row may have been modified by another process."
            )
        }
        DebugLog.print("Updated row in \(table)")
    }

    // MARK: - SQLite-Specific Write Operations (not on protocol)

    /// Insert a new row into the given table.
    /// This method is SQLite-specific and is not part of `DatabaseServiceProtocol`.
    func insertRow(table: String, values: [String: RowEditValue]) async throws {
        guard _isConnected else { throw FileOpenError.notConnected }
        try await connectionManager.withDatabaseWrite { db in
            _ = try SQLiteRowOperations.insertRow(db: db, table: table, values: values)
        }
        DebugLog.print("Inserted row into \(table)")
    }

    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        return try await fetchPrimaryKeys(table: table)
    }

    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        return try await fetchColumnInfo(table: table)
    }

    func connectFile(filePath: String, readOnly: Bool) async throws {
        try await connect(filePath: filePath, readOnly: readOnly)
    }
}

