//
//  SQLStatementSplitterTests.swift
//  TarnTests
//

import Testing
@testable import Tarn

@Suite("SQLStatementSplitter")
struct SQLStatementSplitterTests {

    // MARK: - Basic Splitting

    @Test func splitsSimpleStatements() {
        let sql = "SELECT 1; SELECT 2; SELECT 3;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 3)
        #expect(result[0] == "SELECT 1;")
        #expect(result[1] == " SELECT 2;")
        #expect(result[2] == " SELECT 3;")
    }

    @Test func handlesSingleStatement() {
        let sql = "SELECT * FROM users"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 1)
        #expect(result[0] == "SELECT * FROM users")
    }

    @Test func handlesEmptyInput() {
        let result = SQLStatementSplitter.split("")
        #expect(result.isEmpty)
    }

    @Test func handlesWhitespaceOnly() {
        let result = SQLStatementSplitter.split("   \n\t  ")
        #expect(result.isEmpty)
    }

    @Test func handlesTrailingSemicolon() {
        let sql = "SELECT 1;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 1)
    }

    @Test func handlesNoTrailingSemicolon() {
        let sql = "SELECT 1; SELECT 2"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    // MARK: - String Literals

    @Test func preservesSemicolonInSingleQuotes() {
        let sql = "SELECT 'hello; world'; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
        #expect(result[0].contains("'hello; world'"))
    }

    @Test func handlesEscapedQuotes() {
        let sql = "SELECT 'it''s a test'; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
        #expect(result[0].contains("'it''s a test'"))
    }

    // MARK: - Dollar-Quoted Strings

    @Test func preservesSemicolonInDollarQuotes() {
        let sql = "SELECT $$hello; world$$; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
        #expect(result[0].contains("$$hello; world$$"))
    }

    @Test func handlesTaggedDollarQuotes() {
        let sql = "SELECT $tag$hello; world$tag$; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
        #expect(result[0].contains("$tag$hello; world$tag$"))
    }

    @Test func handlesFunctionWithDollarQuotes() {
        let sql = """
        CREATE FUNCTION test() RETURNS void AS $$
        BEGIN
            INSERT INTO log VALUES ('test;value');
        END;
        $$ LANGUAGE plpgsql;
        SELECT 1;
        """
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
        #expect(result[0].contains("END;"))
        #expect(result[0].contains("$$ LANGUAGE plpgsql;"))
    }

    // MARK: - Comments

    @Test func preservesSemicolonInLineComment() {
        let sql = "SELECT 1 -- this is a comment; not a separator\n; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    @Test func preservesSemicolonInBlockComment() {
        let sql = "SELECT 1 /* comment; here */; SELECT 2;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    @Test func handlesMultilineBlockComment() {
        let sql = """
        SELECT 1 /* this is
        a multiline comment;
        with semicolons */; SELECT 2;
        """
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    // MARK: - Complex Cases

    @Test func handlesCreateTableWithConstraints() {
        let sql = """
        CREATE TABLE users (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100)
        );
        CREATE INDEX idx_name ON users(name);
        """
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    @Test func handlesMixedQuotingStyles() {
        let sql = "INSERT INTO t VALUES ('text', $$more; text$$); SELECT 1;"
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 2)
    }

    @Test func handlesNestedDollarTags() {
        let sql = """
        CREATE FUNCTION outer() RETURNS void AS $outer$
        DECLARE
            code text := $inner$SELECT ';'$inner$;
        BEGIN
            EXECUTE code;
        END;
        $outer$ LANGUAGE plpgsql;
        """
        let result = SQLStatementSplitter.split(sql)
        #expect(result.count == 1)
        #expect(result[0].contains("$outer$ LANGUAGE plpgsql;"))
    }
}
