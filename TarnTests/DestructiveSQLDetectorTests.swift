//
//  DestructiveSQLDetectorTests.swift
//  TarnTests
//
//  Tests for DestructiveSQLDetector and SafeModeState.
//

import XCTest
@testable import Tarn

final class DestructiveSQLDetectorTests: XCTestCase {

    // MARK: - Safe Classification

    func testSelect_isSafe() {
        XCTAssertEqual(DestructiveSQLDetector.classify("SELECT * FROM users"), .safe)
    }

    func testSelectWithWhere_isSafe() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("SELECT id, name FROM users WHERE id = 1"),
            .safe
        )
    }

    func testExplain_isSafe() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("EXPLAIN QUERY PLAN SELECT * FROM t"),
            .safe
        )
    }

    func testPragma_isSafe() {
        XCTAssertEqual(DestructiveSQLDetector.classify("PRAGMA table_info(users)"), .safe)
    }

    func testWith_isSafe() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("WITH cte AS (SELECT 1) SELECT * FROM cte"),
            .safe
        )
    }

    // MARK: - Caution Classification

    func testInsert_isCaution() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("INSERT INTO users (name) VALUES ('Alice')"),
            .caution
        )
    }

    func testCreate_isCaution() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("CREATE TABLE foo (id INTEGER PRIMARY KEY)"),
            .caution
        )
    }

    func testAlter_isCaution() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("ALTER TABLE users ADD COLUMN age INTEGER"),
            .caution
        )
    }

    func testDeleteWithWhere_isCaution() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DELETE FROM users WHERE id = 1"),
            .caution
        )
    }

    func testUpdateWithWhere_isCaution() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("UPDATE users SET name = 'Bob' WHERE id = 2"),
            .caution
        )
    }

    // MARK: - Dangerous Classification

    func testDeleteWithoutWhere_isDangerous() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DELETE FROM users"),
            .dangerous
        )
    }

    func testUpdateWithoutWhere_isDangerous() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("UPDATE users SET active = 0"),
            .dangerous
        )
    }

    func testVacuum_isDangerous() {
        XCTAssertEqual(DestructiveSQLDetector.classify("VACUUM"), .dangerous)
    }

    func testVacuumWithName_isDangerous() {
        XCTAssertEqual(DestructiveSQLDetector.classify("VACUUM main"), .dangerous)
    }

    // MARK: - Destructive Classification

    func testDropTable_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DROP TABLE users"),
            .destructive
        )
    }

    func testDropTableIfExists_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DROP TABLE IF EXISTS users"),
            .destructive
        )
    }

    func testDropIndex_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DROP INDEX idx_users_email"),
            .destructive
        )
    }

    func testDropTrigger_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DROP TRIGGER update_timestamp"),
            .destructive
        )
    }

    func testDropView_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("DROP VIEW active_users"),
            .destructive
        )
    }

    // MARK: - Case Insensitivity

    func testLowercaseDelete_isDangerous() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("delete from orders"),
            .dangerous
        )
    }

    func testMixedCaseDrop_isDestructive() {
        XCTAssertEqual(
            DestructiveSQLDetector.classify("Drop Table sessions"),
            .destructive
        )
    }

    // MARK: - Comparability

    func testDangerLevelComparable() {
        XCTAssertTrue(QueryDangerLevel.safe < QueryDangerLevel.caution)
        XCTAssertTrue(QueryDangerLevel.caution < QueryDangerLevel.dangerous)
        XCTAssertTrue(QueryDangerLevel.dangerous < QueryDangerLevel.destructive)
        XCTAssertFalse(QueryDangerLevel.destructive < QueryDangerLevel.safe)
    }

    func testDangerLevelGreaterOrEqual() {
        XCTAssertTrue(QueryDangerLevel.dangerous >= QueryDangerLevel.dangerous)
        XCTAssertTrue(QueryDangerLevel.destructive >= QueryDangerLevel.dangerous)
        XCTAssertFalse(QueryDangerLevel.caution >= QueryDangerLevel.dangerous)
    }

    // MARK: - Warning Messages

    func testDeleteWithoutWhere_hasWarningMessage() {
        let msg = DestructiveSQLDetector.warningMessage(for: "DELETE FROM orders")
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("ALL rows"))
        XCTAssertTrue(msg!.lowercased().contains("orders"))
    }

    func testUpdateWithoutWhere_hasWarningMessage() {
        let msg = DestructiveSQLDetector.warningMessage(for: "UPDATE products SET price = 0")
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("ALL rows"))
        XCTAssertTrue(msg!.lowercased().contains("products"))
    }

    func testDropTable_hasWarningMessage() {
        let msg = DestructiveSQLDetector.warningMessage(for: "DROP TABLE sessions")
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.lowercased().contains("sessions"))
        XCTAssertTrue(msg!.lowercased().contains("permanently"))
    }

    func testVacuum_hasWarningMessage() {
        let msg = DestructiveSQLDetector.warningMessage(for: "VACUUM")
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.lowercased().contains("vacuum"))
    }

    func testSelect_noWarningMessage() {
        XCTAssertNil(DestructiveSQLDetector.warningMessage(for: "SELECT * FROM t"))
    }

    func testInsert_noWarningMessage() {
        XCTAssertNil(
            DestructiveSQLDetector.warningMessage(
                for: "INSERT INTO t (x) VALUES (1)"
            )
        )
    }

    func testDeleteWithWhere_noWarningMessage() {
        XCTAssertNil(
            DestructiveSQLDetector.warningMessage(
                for: "DELETE FROM t WHERE id = 5"
            )
        )
    }
}

// MARK: - Safe Mode State Tests

final class SafeModeStateTests: XCTestCase {

    // MARK: - Safe Mode OFF (default)

    func testSafeModeOff_selectNeedsNoConfirmation() {
        let state = SafeModeState()
        XCTAssertFalse(state.needsConfirmation(for: "SELECT * FROM t"))
    }

    func testSafeModeOff_insertNeedsNoConfirmation() {
        let state = SafeModeState()
        XCTAssertFalse(state.needsConfirmation(for: "INSERT INTO t (x) VALUES (1)"))
    }

    func testSafeModeOff_deleteWithWhere_needsNoConfirmation() {
        let state = SafeModeState()
        XCTAssertFalse(state.needsConfirmation(for: "DELETE FROM t WHERE id = 1"))
    }

    func testSafeModeOff_deleteWithoutWhere_needsConfirmation() {
        let state = SafeModeState()
        XCTAssertTrue(state.needsConfirmation(for: "DELETE FROM t"))
    }

    func testSafeModeOff_updateWithoutWhere_needsConfirmation() {
        let state = SafeModeState()
        XCTAssertTrue(state.needsConfirmation(for: "UPDATE t SET x = 1"))
    }

    func testSafeModeOff_dropTable_needsConfirmation() {
        let state = SafeModeState()
        XCTAssertTrue(state.needsConfirmation(for: "DROP TABLE t"))
    }

    func testSafeModeOff_dropTable_notBlocked() {
        let state = SafeModeState()
        XCTAssertFalse(state.isBlocked(for: "DROP TABLE t"))
    }

    // MARK: - Safe Mode ON

    func testSafeModeOn_selectNeedsNoConfirmation() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertFalse(state.needsConfirmation(for: "SELECT * FROM t"))
    }

    func testSafeModeOn_insertNeedsConfirmation() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertTrue(state.needsConfirmation(for: "INSERT INTO t (x) VALUES (1)"))
    }

    func testSafeModeOn_deleteWithWhere_needsConfirmation() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertTrue(state.needsConfirmation(for: "DELETE FROM t WHERE id = 1"))
    }

    func testSafeModeOn_dropTable_isBlocked() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertTrue(state.isBlocked(for: "DROP TABLE t"))
    }

    func testSafeModeOn_dropIndex_isBlocked() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertTrue(state.isBlocked(for: "DROP INDEX idx_foo"))
    }

    func testSafeModeOff_nothingBlocked() {
        let state = SafeModeState()
        state.isEnabled = false
        XCTAssertFalse(state.isBlocked(for: "DROP TABLE t"))
    }

    // MARK: - Confirmation Messages

    func testSafeModeOff_deleteWithoutWhere_returnsMessage() {
        let state = SafeModeState()
        let msg = state.confirmationMessage(for: "DELETE FROM sessions")
        XCTAssertNotNil(msg)
    }

    func testSafeModeOn_insert_returnsGenericMessage() {
        let state = SafeModeState()
        state.isEnabled = true
        let msg = state.confirmationMessage(for: "INSERT INTO t (x) VALUES (1)")
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.lowercased().contains("modify data"))
    }

    func testSafeModeOff_select_returnsNilMessage() {
        let state = SafeModeState()
        XCTAssertNil(state.confirmationMessage(for: "SELECT 1"))
    }

    // MARK: - Toolbar Metadata

    func testToolbarLabelWhenEnabled() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertTrue(state.toolbarLabel.lowercased().contains("on"))
    }

    func testToolbarLabelWhenDisabled() {
        let state = SafeModeState()
        state.isEnabled = false
        XCTAssertTrue(state.toolbarLabel.lowercased().contains("off"))
    }

    func testToolbarIconWhenEnabled() {
        let state = SafeModeState()
        state.isEnabled = true
        XCTAssertEqual(state.toolbarIcon, "lock.fill")
    }

    func testToolbarIconWhenDisabled() {
        let state = SafeModeState()
        state.isEnabled = false
        XCTAssertEqual(state.toolbarIcon, "lock.open")
    }
}
