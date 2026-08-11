//
//  DatabaseHealthModelTests.swift
//  PostgresGUITests
//
//  Tests for the DatabaseHealth and IntegrityCheckResult model types.
//

import XCTest
@testable import PostgresGUI

final class DatabaseHealthModelTests: XCTestCase {

    // MARK: - AutoVacuumMode

    func testAutoVacuumModeDisplayNames() {
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.none.displayName, "None")
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.full.displayName, "Full")
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.incremental.displayName, "Incremental")
    }

    func testAutoVacuumModeRawValues() {
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.none.rawValue, 0)
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.full.rawValue, 1)
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode.incremental.rawValue, 2)
    }

    func testAutoVacuumModeFromRawValue() {
        // Use explicit type-qualified member names to avoid `.none` → `Optional.none` ambiguity.
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode(rawValue: 0), DatabaseHealth.AutoVacuumMode.none)
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode(rawValue: 1), DatabaseHealth.AutoVacuumMode.full)
        XCTAssertEqual(DatabaseHealth.AutoVacuumMode(rawValue: 2), DatabaseHealth.AutoVacuumMode.incremental)
        // Unknown raw value must return nil
        let unknown = DatabaseHealth.AutoVacuumMode(rawValue: 99)
        XCTAssertTrue(unknown == nil, "rawValue 99 should not map to any AutoVacuumMode case")
    }

    // MARK: - Fragmentation computation

    func testFragmentationComputationNoFreePages() {
        let health = makeHealth(pageCount: 1000, freePageCount: 0)
        XCTAssertEqual(health.fragmentationPercent, 0.0, accuracy: 0.001)
    }

    func testFragmentationComputationHalfFree() {
        let health = makeHealth(pageCount: 100, freePageCount: 50)
        XCTAssertEqual(health.fragmentationPercent, 50.0, accuracy: 0.001)
    }

    func testFragmentationComputationSmall() {
        let health = makeHealth(pageCount: 3648, freePageCount: 12)
        let expected = 12.0 / 3648.0 * 100.0
        XCTAssertEqual(health.fragmentationPercent, expected, accuracy: 0.001)
    }

    func testFragmentationComputationZeroPages() {
        // Guard against division by zero: should return 0
        let health = makeHealth(pageCount: 0, freePageCount: 0)
        XCTAssertEqual(health.fragmentationPercent, 0.0)
    }

    // MARK: - IntegrityCheckResult

    func testIntegrityCheckResultOK() {
        let result = IntegrityCheckResult(isOK: true, messages: ["ok"], duration: 0.3)
        XCTAssertTrue(result.isOK)
        XCTAssertEqual(result.messages, ["ok"])
        XCTAssertEqual(result.duration, 0.3, accuracy: 0.001)
    }

    func testIntegrityCheckResultWithErrors() {
        let errors = [
            "row 1 missing from index idx_foo",
            "wrong number of entries in index idx_bar"
        ]
        let result = IntegrityCheckResult(isOK: false, messages: errors, duration: 1.25)
        XCTAssertFalse(result.isOK)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertTrue(result.messages.contains("row 1 missing from index idx_foo"))
        XCTAssertEqual(result.duration, 1.25, accuracy: 0.001)
    }

    func testIntegrityCheckResultEmptyMessages() {
        // Edge-case: empty messages means it didn't return "ok", so isOK=false
        let result = IntegrityCheckResult(isOK: false, messages: [], duration: 0.0)
        XCTAssertFalse(result.isOK)
        XCTAssertTrue(result.messages.isEmpty)
    }

    // MARK: - DatabaseHealth field coverage

    func testDatabaseHealthStoredFields() {
        let health = makeHealth(
            fileSizeBytes: 14_680_064,
            pageSize: 4096,
            pageCount: 3584,
            freePageCount: 64,
            journalMode: "wal",
            walFile: true,
            walPages: 8,
            autoVacuum: .none,
            encoding: "UTF-8",
            foreignKeysEnabled: true,
            cacheSize: 2000,
            mmapSize: 268_435_456,
            tableCount: 24,
            indexCount: 18,
            viewCount: 3,
            triggerCount: 2
        )

        XCTAssertEqual(health.fileSizeBytes, 14_680_064)
        XCTAssertEqual(health.pageSize, 4096)
        XCTAssertEqual(health.pageCount, 3584)
        XCTAssertEqual(health.freePageCount, 64)
        XCTAssertEqual(health.journalMode, "wal")
        XCTAssertTrue(health.walFile)
        XCTAssertEqual(health.walPages, 8)
        XCTAssertEqual(health.autoVacuum, .none)
        XCTAssertEqual(health.encoding, "UTF-8")
        XCTAssertTrue(health.foreignKeysEnabled)
        XCTAssertEqual(health.cacheSize, 2000)
        XCTAssertEqual(health.mmapSize, 268_435_456)
        XCTAssertEqual(health.tableCount, 24)
        XCTAssertEqual(health.indexCount, 18)
        XCTAssertEqual(health.viewCount, 3)
        XCTAssertEqual(health.triggerCount, 2)
    }

    // MARK: - Helpers

    private func makeHealth(
        fileSizeBytes: Int64 = 0,
        pageSize: Int = 4096,
        pageCount: Int,
        freePageCount: Int,
        journalMode: String = "delete",
        walFile: Bool = false,
        walPages: Int? = nil,
        autoVacuum: DatabaseHealth.AutoVacuumMode = .none,
        encoding: String = "UTF-8",
        foreignKeysEnabled: Bool = false,
        cacheSize: Int = 2000,
        mmapSize: Int64 = 0,
        tableCount: Int = 0,
        indexCount: Int = 0,
        viewCount: Int = 0,
        triggerCount: Int = 0
    ) -> DatabaseHealth {
        DatabaseHealth(
            fileSizeBytes: fileSizeBytes,
            pageSize: pageSize,
            pageCount: pageCount,
            freePageCount: freePageCount,
            journalMode: journalMode,
            walFile: walFile,
            walPages: walPages,
            autoVacuum: autoVacuum,
            encoding: encoding,
            foreignKeysEnabled: foreignKeysEnabled,
            cacheSize: cacheSize,
            mmapSize: mmapSize,
            tableCount: tableCount,
            indexCount: indexCount,
            viewCount: viewCount,
            triggerCount: triggerCount
        )
    }
}
