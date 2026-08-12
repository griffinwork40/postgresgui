//
//  QueryDecisionsTests.swift
//  TarnTests
//
//  Unit tests for query-related decision logic.
//

import Foundation
import Testing
@testable import Tarn

// MARK: - Cache Decision Tests

@Suite("Cache Decisions")
struct CacheDecisionTests {

    @Suite("shouldUseCachedResults")
    struct ShouldUseCachedResultsTests {

        @Test func returnsFalseWhenNoResults() {
            let result = shouldUseCachedResults(
                hasResults: false,
                cachedTableId: "table1",
                selectedTableId: "table1"
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenCachedTableIdIsNil() {
            let result = shouldUseCachedResults(
                hasResults: true,
                cachedTableId: nil,
                selectedTableId: "table1"
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenSelectedTableIdIsNil() {
            let result = shouldUseCachedResults(
                hasResults: true,
                cachedTableId: "table1",
                selectedTableId: nil
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenTableIdsDontMatch() {
            let result = shouldUseCachedResults(
                hasResults: true,
                cachedTableId: "table1",
                selectedTableId: "table2"
            )
            #expect(result == false)
        }

        @Test func returnsTrueWhenAllConditionsMet() {
            let result = shouldUseCachedResults(
                hasResults: true,
                cachedTableId: "users_table",
                selectedTableId: "users_table"
            )
            #expect(result == true)
        }
    }

    @Suite("shouldClearResultsOnTableChange")
    struct ShouldClearResultsTests {

        @Test func returnsFalseWhenTableUnchanged() {
            let result = shouldClearResultsOnTableChange(
                oldTableId: "table1",
                newTableId: "table1",
                hasCachedResultsForNewTable: false
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenHasCachedResults() {
            let result = shouldClearResultsOnTableChange(
                oldTableId: "table1",
                newTableId: "table2",
                hasCachedResultsForNewTable: true
            )
            #expect(result == false)
        }

        @Test func returnsTrueWhenTableChangedAndNoCache() {
            let result = shouldClearResultsOnTableChange(
                oldTableId: "table1",
                newTableId: "table2",
                hasCachedResultsForNewTable: false
            )
            #expect(result == true)
        }

        @Test func returnsTrueWhenSelectingFirstTable() {
            let result = shouldClearResultsOnTableChange(
                oldTableId: nil,
                newTableId: "table1",
                hasCachedResultsForNewTable: false
            )
            #expect(result == true)
        }
    }
}

// MARK: - Table Refresh Decision Tests

@Suite("Table Refresh Decisions")
struct TableRefreshDecisionTests {

    @Suite("shouldRefreshTableAfterMutation")
    struct ShouldRefreshTests {

        @Test func returnsFalseWhenMutatedTableIsNil() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: nil,
                selectedTableName: "users"
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenSelectedTableIsNil() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: "users",
                selectedTableName: nil
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenTablesDontMatch() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: "orders",
                selectedTableName: "users"
            )
            #expect(result == false)
        }

        @Test func returnsTrueWhenTablesMatch() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: "users",
                selectedTableName: "users"
            )
            #expect(result == true)
        }

        @Test func matchesCaseInsensitive() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: "Users",
                selectedTableName: "users"
            )
            #expect(result == true)
        }

        @Test func matchesSchemaQualifiedToSimple() {
            let result = shouldRefreshTableAfterMutation(
                mutatedTableName: "public.users",
                selectedTableName: "users"
            )
            #expect(result == true)
        }
    }

    @Suite("tableNamesMatch")
    struct TableNamesMatchTests {

        @Test func matchesIdenticalNames() {
            #expect(tableNamesMatch("users", "users") == true)
        }

        @Test func matchesDifferentCase() {
            #expect(tableNamesMatch("Users", "users") == true)
            #expect(tableNamesMatch("USERS", "users") == true)
            #expect(tableNamesMatch("users", "USERS") == true)
        }

        @Test func matchesSchemaQualifiedNames() {
            #expect(tableNamesMatch("public.users", "users") == true)
            #expect(tableNamesMatch("users", "public.users") == true)
            #expect(tableNamesMatch("schema1.users", "schema2.users") == true)
        }

        @Test func doesNotMatchDifferentNames() {
            #expect(tableNamesMatch("users", "orders") == false)
            #expect(tableNamesMatch("public.users", "public.orders") == false)
        }
    }
}

// MARK: - Rollback Safety Tests

@Suite("Rollback Safety")
struct RollbackSafetyTests {

    @Test func safeToRollbackWhenVersionUnchanged() {
        #expect(isSafeToRollback(versionAtOperationStart: 10, currentVersion: 10) == true)
    }

    @Test func notSafeWhenVersionIncremented() {
        #expect(isSafeToRollback(versionAtOperationStart: 10, currentVersion: 11) == false)
    }

    @Test func notSafeWhenVersionDecreasedUnexpectedly() {
        #expect(isSafeToRollback(versionAtOperationStart: 10, currentVersion: 9) == false)
    }
}

// MARK: - Pagination Tests

@Suite("Pagination")
struct PaginationTests {

    @Suite("hasMorePages")
    struct HasMorePagesTests {

        @Test func returnsFalseWhenFewerRowsThanPageSize() {
            #expect(hasMorePages(fetchedRowCount: 50, pageSize: 100) == false)
        }

        @Test func returnsFalseWhenExactlyPageSize() {
            #expect(hasMorePages(fetchedRowCount: 100, pageSize: 100) == false)
        }

        @Test func returnsTrueWhenMoreThanPageSize() {
            // We fetch pageSize + 1 to detect if there are more pages
            #expect(hasMorePages(fetchedRowCount: 101, pageSize: 100) == true)
        }

        @Test func handlesSmallPageSizes() {
            #expect(hasMorePages(fetchedRowCount: 11, pageSize: 10) == true)
            #expect(hasMorePages(fetchedRowCount: 10, pageSize: 10) == false)
        }
    }

    @Suite("canGoToPreviousPage")
    struct CanGoToPreviousPageTests {

        @Test func returnsFalseOnFirstPage() {
            #expect(canGoToPreviousPage(currentPage: 0) == false)
        }

        @Test func returnsTrueOnSecondPage() {
            #expect(canGoToPreviousPage(currentPage: 1) == true)
        }

        @Test func returnsTrueOnLaterPages() {
            #expect(canGoToPreviousPage(currentPage: 5) == true)
            #expect(canGoToPreviousPage(currentPage: 100) == true)
        }
    }

    @Suite("calculateOffset")
    struct CalculateOffsetTests {

        @Test func firstPageHasZeroOffset() {
            #expect(calculateOffset(page: 0, pageSize: 100) == 0)
        }

        @Test func secondPageHasPageSizeOffset() {
            #expect(calculateOffset(page: 1, pageSize: 100) == 100)
        }

        @Test func calculatesCorrectlyForLaterPages() {
            #expect(calculateOffset(page: 2, pageSize: 100) == 200)
            #expect(calculateOffset(page: 5, pageSize: 50) == 250)
            #expect(calculateOffset(page: 10, pageSize: 25) == 250)
        }
    }
}
