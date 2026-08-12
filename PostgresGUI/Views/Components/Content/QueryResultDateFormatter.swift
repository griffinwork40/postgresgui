//
//  QueryResultDateFormatter.swift
//  PostgresGUI
//
//  Date parsing and formatting helpers for query result cell values.
//  Extracted from QueryResultsComponent to keep that file under 350 lines.
//

import Foundation

// MARK: - Query Result Date Formatter

enum QueryResultDateFormatter {

    // MARK: - Public API

    static let maxDateParseLength = 64

    /// Format a raw cell value, applying date formatting when the value looks
    /// like a timestamp.  Returns "NULL" for nil, the original string when no
    /// date is detected, or the value re-formatted according to `dateFormat`.
    static func formatValue(_ value: String?, dateFormat: QueryResultsDateFormat) -> String {
        guard let value = value else { return "NULL" }
        guard shouldAttemptDateParsing(value) else { return value }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldAttemptDateParsing(trimmedValue) else { return value }
        guard let date = parseDate(from: trimmedValue) else { return value }

        switch dateFormat {
        case .relative:
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        default:
            return dateFormat.formatter.string(from: date)
        }
    }

    /// Returns true when the value is short enough and contains both a digit
    /// and a date-like separator, making it worth attempting a full parse.
    static func shouldAttemptDateParsing(_ value: String) -> Bool {
        guard !value.isEmpty, !isLongerThanDateParseLimit(value) else { return false }

        var hasDigit = false
        var hasDateMarker = false

        for scalar in value.unicodeScalars {
            if !hasDigit, CharacterSet.decimalDigits.contains(scalar) {
                hasDigit = true
            }

            if !hasDateMarker {
                switch scalar {
                case "-", "/", ":", "T", "t":
                    hasDateMarker = true
                default:
                    break
                }
            }

            if hasDigit && hasDateMarker {
                return true
            }
        }

        return false
    }

    // MARK: - Private Parsing

    private static func parseDate(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        if let date = iso8601ParserWithFractional.date(from: value) { return date }
        if let date = iso8601Parser.date(from: value) { return date }

        for formatter in customParsers {
            if let date = formatter.date(from: value) { return date }
        }

        return nil
    }

    private static func isLongerThanDateParseLimit(_ value: String) -> Bool {
        var count = 0
        for _ in value.utf8 {
            count += 1
            if count > maxDateParseLength { return true }
        }
        return false
    }

    private static func makeParsingFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Formatters (lazy statics)

    private static let iso8601Parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601ParserWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let customParsers: [DateFormatter] = [
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss.SSS"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ssZ"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss.SSSZ"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        makeParsingFormatter("yyyy-MM-dd")
    ]

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
