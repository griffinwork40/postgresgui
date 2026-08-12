//
//  QueryTypeDetectorTests.swift
//  TarnTests
//
//  Unit tests for SQL query type detection and table name extraction.
//

import Foundation
import Testing
@testable import Tarn

// MARK: - Query Type Detection Tests

@Suite("QueryTypeDetector")
struct QueryTypeDetectorTests {

    // MARK: - Basic Query Type Detection

    @Suite("detect")
    struct DetectTests {

        @Test func detectsSimpleSelect() {
            #expect(QueryTypeDetector.detect("SELECT * FROM users") == .select)
        }

        @Test func detectsSelectWithWhitespace() {
            #expect(QueryTypeDetector.detect("  SELECT * FROM users  ") == .select)
            #expect(QueryTypeDetector.detect("\n\tSELECT id FROM users") == .select)
        }

        @Test func detectsSelectCaseInsensitive() {
            #expect(QueryTypeDetector.detect("select * from users") == .select)
            #expect(QueryTypeDetector.detect("Select * From users") == .select)
        }

        @Test func detectsCTEAsSelect() {
            let cte = "WITH active_users AS (SELECT * FROM users WHERE active) SELECT * FROM active_users"
            #expect(QueryTypeDetector.detect(cte) == .select)
        }

        @Test func detectsInsert() {
            #expect(QueryTypeDetector.detect("INSERT INTO users (name) VALUES ('test')") == .insert)
            #expect(QueryTypeDetector.detect("insert into users values (1)") == .insert)
        }

        @Test func detectsInsertWithReturning() {
            let sql = "INSERT INTO users (name) VALUES ('test') RETURNING id"
            #expect(QueryTypeDetector.detect(sql) == .insert)
        }

        @Test func detectsUpdate() {
            #expect(QueryTypeDetector.detect("UPDATE users SET name = 'test'") == .update)
            #expect(QueryTypeDetector.detect("update users set active = true where id = 1") == .update)
        }

        @Test func detectsDelete() {
            #expect(QueryTypeDetector.detect("DELETE FROM users WHERE id = 1") == .delete)
            #expect(QueryTypeDetector.detect("delete from users") == .delete)
        }

        @Test func detectsCreateTable() {
            #expect(QueryTypeDetector.detect("CREATE TABLE users (id INT)") == .createTable)
            #expect(QueryTypeDetector.detect("create table users (id int)") == .createTable)
        }

        @Test func detectsCreateTempTable() {
            #expect(QueryTypeDetector.detect("CREATE TEMP TABLE tmp (id INT)") == .createTable)
            #expect(QueryTypeDetector.detect("CREATE TEMPORARY TABLE tmp (id INT)") == .createTable)
        }

        @Test func detectsDropTable() {
            #expect(QueryTypeDetector.detect("DROP TABLE users") == .dropTable)
            #expect(QueryTypeDetector.detect("DROP TABLE IF EXISTS users") == .dropTable)
        }

        @Test func detectsAlterTable() {
            #expect(QueryTypeDetector.detect("ALTER TABLE users ADD COLUMN email TEXT") == .alterTable)
            #expect(QueryTypeDetector.detect("alter table users drop column name") == .alterTable)
        }

        @Test func detectsOtherStatements() {
            #expect(QueryTypeDetector.detect("CREATE INDEX idx ON users(name)") == .other)
            #expect(QueryTypeDetector.detect("GRANT SELECT ON users TO reader") == .other)
            #expect(QueryTypeDetector.detect("VACUUM users") == .other)
            #expect(QueryTypeDetector.detect("EXPLAIN SELECT * FROM users") == .other)
        }
    }

    // MARK: - Mutation Detection

    @Suite("isMutation")
    struct IsMutationTests {

        @Test func selectIsNotMutation() {
            #expect(QueryType.select.isMutation == false)
        }

        @Test func otherIsNotMutation() {
            #expect(QueryType.other.isMutation == false)
        }

        @Test func insertIsMutation() {
            #expect(QueryType.insert.isMutation == true)
        }

        @Test func updateIsMutation() {
            #expect(QueryType.update.isMutation == true)
        }

        @Test func deleteIsMutation() {
            #expect(QueryType.delete.isMutation == true)
        }

        @Test func ddlAreMutations() {
            #expect(QueryType.createTable.isMutation == true)
            #expect(QueryType.dropTable.isMutation == true)
            #expect(QueryType.alterTable.isMutation == true)
        }
    }

    // MARK: - Table Name Extraction

    @Suite("extractTableName")
    struct ExtractTableNameTests {

        @Test func extractsFromInsert() {
            #expect(QueryTypeDetector.extractTableName("INSERT INTO users VALUES (1)") == "users")
            #expect(QueryTypeDetector.extractTableName("insert into orders (id) values (1)") == "orders")
        }

        @Test func extractsFromUpdate() {
            #expect(QueryTypeDetector.extractTableName("UPDATE users SET name = 'test'") == "users")
            #expect(QueryTypeDetector.extractTableName("update products set price = 10") == "products")
        }

        @Test func extractsFromDelete() {
            #expect(QueryTypeDetector.extractTableName("DELETE FROM users WHERE id = 1") == "users")
            #expect(QueryTypeDetector.extractTableName("delete from orders") == "orders")
        }

        @Test func extractsFromCreateTable() {
            #expect(QueryTypeDetector.extractTableName("CREATE TABLE users (id INT)") == "users")
            #expect(QueryTypeDetector.extractTableName("CREATE TEMP TABLE tmp_data (id INT)") == "tmp_data")
            #expect(QueryTypeDetector.extractTableName("CREATE TABLE IF NOT EXISTS users (id INT)") == "users")
        }

        @Test func extractsFromDropTable() {
            #expect(QueryTypeDetector.extractTableName("DROP TABLE users") == "users")
            #expect(QueryTypeDetector.extractTableName("DROP TABLE IF EXISTS old_data") == "old_data")
        }

        @Test func extractsFromAlterTable() {
            #expect(QueryTypeDetector.extractTableName("ALTER TABLE users ADD COLUMN email TEXT") == "users")
        }

        @Test func handlesQuotedTableNames() {
            #expect(QueryTypeDetector.extractTableName("INSERT INTO \"Users\" VALUES (1)") == "Users")
            #expect(QueryTypeDetector.extractTableName("UPDATE \"Order Items\" SET qty = 1") == "Order Items")
        }

        @Test func handlesQuotedTableNamesWithSpacesInAllStatements() {
            #expect(QueryTypeDetector.extractTableName("INSERT INTO \"Order Items\" VALUES (1)") == "Order Items")
            #expect(QueryTypeDetector.extractTableName("DELETE FROM \"Order Items\" WHERE id = 1") == "Order Items")
            #expect(QueryTypeDetector.extractTableName("CREATE TABLE \"Order Items\" (id INT)") == "Order Items")
            #expect(QueryTypeDetector.extractTableName("DROP TABLE \"Order Items\"") == "Order Items")
            #expect(QueryTypeDetector.extractTableName("ALTER TABLE \"Order Items\" ADD COLUMN x INT") == "Order Items")
        }

        @Test func handlesSchemaQualifiedNames() {
            #expect(QueryTypeDetector.extractTableName("INSERT INTO public.users VALUES (1)") == "users")
            #expect(QueryTypeDetector.extractTableName("UPDATE myschema.products SET price = 10") == "products")
        }

        @Test func returnsNilForSelect() {
            #expect(QueryTypeDetector.extractTableName("SELECT * FROM users") == nil)
        }

        @Test func returnsNilForOther() {
            #expect(QueryTypeDetector.extractTableName("CREATE INDEX idx ON users(name)") == nil)
        }
    }
}

// MARK: - Schema Detection Tests

@Suite("Schema Detection")
struct SchemaDetectionTests {

    @Test func detectsSchemaModifyingQueries() {
        #expect(isSchemaModifyingQuery("CREATE TABLE users (id INT)") == true)
        #expect(isSchemaModifyingQuery("DROP TABLE users") == true)
        #expect(isSchemaModifyingQuery("ALTER TABLE users ADD COLUMN x INT") == true)
        #expect(isSchemaModifyingQuery("CREATE TEMP TABLE tmp (id INT)") == true)
        #expect(isSchemaModifyingQuery("CREATE TEMPORARY TABLE tmp (id INT)") == true)
    }

    @Test func nonSchemaQueriesReturnFalse() {
        #expect(isSchemaModifyingQuery("SELECT * FROM users") == false)
        #expect(isSchemaModifyingQuery("INSERT INTO users VALUES (1)") == false)
        #expect(isSchemaModifyingQuery("UPDATE users SET x = 1") == false)
        #expect(isSchemaModifyingQuery("DELETE FROM users") == false)
    }

    @Test func detectsDropTableQuery() {
        #expect(isDropTableQuery("DROP TABLE users") == true)
        #expect(isDropTableQuery("DROP TABLE IF EXISTS users") == true)
        #expect(isDropTableQuery("drop table users") == true)
    }

    @Test func nonDropTableQueriesReturnFalse() {
        #expect(isDropTableQuery("CREATE TABLE users (id INT)") == false)
        #expect(isDropTableQuery("SELECT * FROM users") == false)
        #expect(isDropTableQuery("DELETE FROM users") == false)
    }
}
