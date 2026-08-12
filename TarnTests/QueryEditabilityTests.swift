//
//  QueryEditabilityTests.swift
//  TarnTests
//
//  Unit tests for query editability detection.
//

import Foundation
import Testing
@testable import Tarn

@Suite("QueryEditability")
struct QueryEditabilityTests {

    // MARK: - Explicit Source Table (Table Click)

    @Suite("Explicit Source Table")
    struct ExplicitSourceTests {

        @Test func tableClickIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users",
                sourceTable: "users",
                sourceSchema: "public"
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
            #expect(result.schemaName == "public")
            #expect(result.disabledReason == nil)
        }

        @Test func tableClickWithoutSchemaIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users",
                sourceTable: "users",
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
            #expect(result.schemaName == nil)
        }

        @Test func explicitSourceTrumpsQueryAnalysis() {
            // Even if the query looks complex, explicit source makes it editable
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users WHERE created_at > NOW()",
                sourceTable: "users",
                sourceSchema: "public"
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
        }
    }

    // MARK: - Simple SELECT Queries (Editable)

    @Suite("Simple SELECT")
    struct SimpleSelectTests {

        @Test func selectStarIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
        }

        @Test func selectColumnsIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT id, name, email FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
        }

        @Test func selectWithWhereIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users WHERE active = true",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
        }

        @Test func selectWithOrderByIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users ORDER BY created_at DESC",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
        }

        @Test func selectWithLimitIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users LIMIT 10",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
        }

        @Test func selectWithOffsetIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users LIMIT 10 OFFSET 20",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
        }

        @Test func selectWithSchemaIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM public.users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
            #expect(result.schemaName == "public")
        }

        @Test func caseInsensitiveDetection() {
            let context = QueryEditabilityContext(
                query: "select * from users where id = 1",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
        }

        @Test func selectWithQuotedTableIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM \"My Table\"",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "My Table")
        }

        @Test func selectWithQuotedSchemaAndTableIsEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM \"my schema\".\"My Table\"",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "My Table")
            #expect(result.schemaName == "my schema")
        }
    }

    // MARK: - JOIN Queries (Not Editable)

    @Suite("JOIN Queries")
    struct JoinTests {

        @Test func innerJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users u JOIN orders o ON u.id = o.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func explicitInnerJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func leftJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users LEFT JOIN orders ON users.id = orders.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func rightJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users RIGHT JOIN orders ON users.id = orders.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func fullJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users FULL JOIN orders ON users.id = orders.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func crossJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users CROSS JOIN products",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Joined Results")
        }

        @Test func implicitJoinIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users, orders WHERE users.id = orders.user_id",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Multi-Table Results")
        }
    }

    // MARK: - Aggregate Queries (Not Editable)

    @Suite("Aggregate Queries")
    struct AggregateTests {

        @Test func countIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT COUNT(*) FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func sumIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT SUM(amount) FROM orders",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func avgIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT AVG(price) FROM products",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func minIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT MIN(created_at) FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func maxIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT MAX(price) FROM products",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func arrayAggIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT ARRAY_AGG(name) FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func stringAggIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT STRING_AGG(name, ', ') FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Aggregated Data")
        }

        @Test func groupByIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT status, COUNT(*) FROM orders GROUP BY status",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Grouped Data")
        }
    }

    // MARK: - DISTINCT Queries (Not Editable)

    @Suite("DISTINCT Queries")
    struct DistinctTests {

        @Test func distinctIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT DISTINCT country FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Distinct Results")
        }

        @Test func distinctMultipleColumnsIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT DISTINCT country, city FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Distinct Results")
        }
    }

    // MARK: - Combined Queries (Not Editable)

    @Suite("Combined Queries")
    struct CombinedTests {

        @Test func unionIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users UNION SELECT * FROM admins",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Combined Results")
        }

        @Test func unionAllIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users UNION ALL SELECT * FROM admins",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Combined Results")
        }

        @Test func intersectIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users INTERSECT SELECT * FROM premium_users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Combined Results")
        }

        @Test func exceptIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users EXCEPT SELECT * FROM banned_users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Combined Results")
        }
    }

    // MARK: - CTE Queries (Not Editable)

    @Suite("CTE Queries")
    struct CTETests {

        @Test func cteIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "WITH active AS (SELECT * FROM users WHERE active) SELECT * FROM active",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit CTE Results")
        }

        @Test func cteWithMultipleExpressionsIsNotEditable() {
            let context = QueryEditabilityContext(
                query: """
                    WITH active AS (SELECT * FROM users WHERE active),
                         orders AS (SELECT * FROM orders WHERE status = 'pending')
                    SELECT * FROM active
                    """,
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit CTE Results")
        }
    }

    // MARK: - Window Functions (Not Editable)

    @Suite("Window Functions")
    struct WindowFunctionTests {

        @Test func rowNumberIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT *, ROW_NUMBER() OVER (ORDER BY id) FROM users",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Window Function Results")
        }

        @Test func rankIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT *, RANK() OVER (ORDER BY score DESC) FROM players",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Window Function Results")
        }

        @Test func partitionByIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT *, SUM(amount) OVER (PARTITION BY user_id) FROM orders",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Window Function Results")
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test func emptyQueryIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Query Results")
        }

        @Test func whitespaceOnlyQueryIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "   \n\t   ",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
        }

        @Test func unparseableQueryIsNotEditable() {
            let context = QueryEditabilityContext(
                query: "SELECT something weird here",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(!result.isEditable)
            #expect(result.disabledReason?.title == "Can't Edit Query Results")
        }

        @Test func selectWithSubqueryInWhereIsEditable() {
            // Subquery in WHERE is okay - main query is still single table
            let context = QueryEditabilityContext(
                query: "SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)",
                sourceTable: nil,
                sourceSchema: nil
            )
            let result = determineQueryEditability(context)
            #expect(result.isEditable)
            #expect(result.tableName == "users")
        }
    }
}
