//
//  DatabaseDiscoveryTests.swift
//  PostgresGUITests
//
//  Tests for DatabaseDiscoveryService: extension detection, magic-byte detection,
//  skip rules (.app bundles), max-depth enforcement, and cancellation.
//

import XCTest
@testable import PostgresGUI

final class DatabaseDiscoveryTests: XCTestCase {

    private var tempDir: URL!
    private let service = DatabaseDiscoveryService()

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appendingPathComponent("DDTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helper

    private func makeFile(name: String, content: Data = Data(), in dir: URL? = nil) throws -> URL {
        let directory = dir ?? tempDir!
        let url = directory.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    private static let sqliteMagic: Data = {
        var bytes: [UInt8] = [
            0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
            0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
        ]
        // Pad to 100 bytes so it looks like a real file
        bytes += [UInt8](repeating: 0, count: 84)
        return Data(bytes)
    }()

    // MARK: - Tests

    // MARK: Known extensions are detected

    func testSQLiteExtensionDetected() async throws {
        try makeFile(name: "mydb.sqlite", content: Data("hello".utf8))
        let results = try await service.scan(directory: tempDir) { _ in }
        let names = results.map(\.fileName)
        XCTAssertTrue(names.contains("mydb.sqlite"), "Expected mydb.sqlite in \(names)")
    }

    func testDbExtensionDetected() async throws {
        try makeFile(name: "app.db", content: Data("x".utf8))
        let results = try await service.scan(directory: tempDir) { _ in }
        XCTAssertTrue(results.map(\.fileName).contains("app.db"))
    }

    func testSQLite3ExtensionDetected() async throws {
        try makeFile(name: "data.sqlite3", content: Data("y".utf8))
        let results = try await service.scan(directory: tempDir) { _ in }
        XCTAssertTrue(results.map(\.fileName).contains("data.sqlite3"))
    }

    // MARK: Magic-byte detection for extensionless files

    func testMagicByteDetectionForExtensionlessFile() async throws {
        // File with no extension but valid SQLite magic header should be detected
        try makeFile(name: "rawdb", content: Self.sqliteMagic)
        let results = try await service.scan(directory: tempDir) { _ in }
        XCTAssertTrue(
            results.map(\.fileName).contains("rawdb"),
            "Magic-byte detection should find 'rawdb'"
        )
    }

    func testExtensionlessFileWithoutMagicIsSkipped() async throws {
        try makeFile(name: "notadb", content: Data("just text content here".utf8))
        let results = try await service.scan(directory: tempDir) { _ in }
        XCTAssertFalse(
            results.map(\.fileName).contains("notadb"),
            "Plain text file without known extension should not appear"
        )
    }

    // MARK: .app bundles skipped

    func testAppBundlesAreSkipped() async throws {
        // Create a fake .app bundle directory containing a sqlite file
        let appDir = tempDir.appendingPathComponent("MyApp.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try makeFile(name: "db.sqlite", content: Self.sqliteMagic, in: appDir)

        // Also place a sqlite file at the root so we have at least one result to verify scan ran
        try makeFile(name: "root.sqlite", content: Data("a".utf8))

        let results = try await service.scan(directory: tempDir) { _ in }
        let names = results.map(\.fileName)
        XCTAssertFalse(names.contains("db.sqlite"), ".app bundle contents should be skipped")
        XCTAssertTrue(names.contains("root.sqlite"), "Root-level db should still appear")
    }

    // MARK: Max depth limit

    func testMaxDepthLimitEnforced() async throws {
        // Build a 6-level deep directory chain (beyond max depth of 5)
        var current = tempDir!
        for i in 1...6 {
            current = current.appendingPathComponent("level\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        }
        // Place a sqlite file at depth 6 (should be skipped)
        try makeFile(name: "deep.sqlite", content: Self.sqliteMagic, in: current)

        // Place one at depth 3 (should be found)
        let level3 = tempDir
            .appendingPathComponent("level1")
            .appendingPathComponent("level2")
            .appendingPathComponent("level3")
        try makeFile(name: "shallow.sqlite", content: Data("ok".utf8), in: level3)

        let results = try await service.scan(directory: tempDir) { _ in }
        let names = results.map(\.fileName)
        XCTAssertFalse(names.contains("deep.sqlite"), "File at depth 6 should be skipped")
        XCTAssertTrue(names.contains("shallow.sqlite"), "File at depth 3 should be found")
    }

    // MARK: Cancellation

    func testScanCancellation() async throws {
        // Populate many files so the scan takes meaningful time
        for i in 0..<200 {
            try makeFile(name: "file\(i).sqlite", content: Data("content\(i)".utf8))
        }

        let task = Task {
            try await service.scan(directory: tempDir) { _ in }
        }
        // Cancel quickly
        task.cancel()

        do {
            _ = try await task.value
            // Allowed: the scan may complete if it was fast enough.
        } catch is CancellationError {
            // Expected when the task is cancelled mid-scan.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // If we reach here without hanging, cancellation is working.
    }

    // MARK: WAL detection

    func testWALDetection() async throws {
        try makeFile(name: "wal.sqlite", content: Data("d".utf8))
        try makeFile(name: "wal.sqlite-wal", content: Data("w".utf8))

        let results = try await service.scan(directory: tempDir) { _ in }
        let db = results.first { $0.fileName == "wal.sqlite" }
        XCTAssertNotNil(db)
        XCTAssertTrue(db?.hasWAL == true, "WAL file alongside should set hasWAL=true")
    }

    // MARK: DiscoveredDatabase.formattedFileSize

    func testFormattedFileSizeBytes() {
        let db = DiscoveredDatabase(fileName: "t", filePath: URL(fileURLWithPath: "/t"), fileSize: 512, lastModified: Date(), hasWAL: false)
        XCTAssertEqual(db.formattedFileSize, "512 B")
    }

    func testFormattedFileSizeKB() {
        let db = DiscoveredDatabase(fileName: "t", filePath: URL(fileURLWithPath: "/t"), fileSize: 2048, lastModified: Date(), hasWAL: false)
        XCTAssertEqual(db.formattedFileSize, "2.0 KB")
    }

    func testFormattedFileSizeMB() {
        let db = DiscoveredDatabase(fileName: "t", filePath: URL(fileURLWithPath: "/t"), fileSize: 5 * 1_024 * 1_024, lastModified: Date(), hasWAL: false)
        XCTAssertEqual(db.formattedFileSize, "5.0 MB")
    }
}
