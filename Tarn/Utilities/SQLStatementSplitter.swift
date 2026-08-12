//
//  SQLStatementSplitter.swift
//  Tarn
//
//  Splits SQL scripts into individual statements for sequential execution.
//  PostgresNIO doesn't support the simple query protocol in its async API,
//  so multi-statement scripts must be split and executed one at a time.
//

import Foundation

enum SQLStatementSplitter {
    /// Split SQL into individual statements, handling:
    /// - Dollar-quoted strings ($$...$$, $tag$...$tag$)
    /// - Single-quoted strings ('...')
    /// - Line comments (--)
    /// - Block comments (/* */)
    static func split(_ sql: String) -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        var i = sql.startIndex

        while i < sql.endIndex {
            let char = sql[i]

            // Check for dollar-quoted string ($$...$$ or $tag$...$tag$)
            if char == "$" {
                let dollarStart = i
                var tagEnd = sql.index(after: i)

                // Find the end of the dollar tag
                while tagEnd < sql.endIndex && (sql[tagEnd].isLetter || sql[tagEnd].isNumber || sql[tagEnd] == "_") {
                    tagEnd = sql.index(after: tagEnd)
                }

                if tagEnd < sql.endIndex && sql[tagEnd] == "$" {
                    let tag = String(sql[dollarStart...tagEnd])
                    currentStatement.append(tag)
                    i = sql.index(after: tagEnd)

                    // Find the closing tag
                    while i < sql.endIndex {
                        if sql[i] == "$" {
                            let possibleTagStart = i
                            var possibleTagEnd = sql.index(after: i)

                            while possibleTagEnd < sql.endIndex && (sql[possibleTagEnd].isLetter || sql[possibleTagEnd].isNumber || sql[possibleTagEnd] == "_") {
                                possibleTagEnd = sql.index(after: possibleTagEnd)
                            }

                            if possibleTagEnd < sql.endIndex && sql[possibleTagEnd] == "$" {
                                let possibleTag = String(sql[possibleTagStart...possibleTagEnd])
                                if possibleTag == tag {
                                    currentStatement.append(String(sql[possibleTagStart...possibleTagEnd]))
                                    i = sql.index(after: possibleTagEnd)
                                    break
                                }
                            }
                        }
                        currentStatement.append(sql[i])
                        i = sql.index(after: i)
                    }
                    continue
                }
            }

            // Check for single-quoted string
            if char == "'" {
                currentStatement.append(char)
                i = sql.index(after: i)
                while i < sql.endIndex {
                    currentStatement.append(sql[i])
                    if sql[i] == "'" {
                        let next = sql.index(after: i)
                        if next < sql.endIndex && sql[next] == "'" {
                            // Escaped quote
                            currentStatement.append(sql[next])
                            i = sql.index(after: next)
                        } else {
                            i = sql.index(after: i)
                            break
                        }
                    } else {
                        i = sql.index(after: i)
                    }
                }
                continue
            }

            // Check for line comment (--)
            if char == "-" {
                let next = sql.index(after: i)
                if next < sql.endIndex && sql[next] == "-" {
                    currentStatement.append(char)
                    currentStatement.append(sql[next])
                    i = sql.index(after: next)
                    while i < sql.endIndex && sql[i] != "\n" {
                        currentStatement.append(sql[i])
                        i = sql.index(after: i)
                    }
                    continue
                }
            }

            // Check for block comment (/* */)
            if char == "/" {
                let next = sql.index(after: i)
                if next < sql.endIndex && sql[next] == "*" {
                    currentStatement.append(char)
                    currentStatement.append(sql[next])
                    i = sql.index(after: next)
                    while i < sql.endIndex {
                        let nextChar = sql[i]
                        currentStatement.append(nextChar)
                        if nextChar == "*" {
                            let afterStar = sql.index(after: i)
                            if afterStar < sql.endIndex && sql[afterStar] == "/" {
                                currentStatement.append(sql[afterStar])
                                i = sql.index(after: afterStar)
                                break
                            }
                        }
                        i = sql.index(after: i)
                    }
                    continue
                }
            }

            // Check for statement terminator
            if char == ";" {
                currentStatement.append(char)
                statements.append(currentStatement)
                currentStatement = ""
                i = sql.index(after: i)
                continue
            }

            // Regular character
            currentStatement.append(char)
            i = sql.index(after: i)
        }

        // Don't forget any remaining statement without trailing semicolon
        let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            statements.append(currentStatement)
        }

        return statements
    }
}
