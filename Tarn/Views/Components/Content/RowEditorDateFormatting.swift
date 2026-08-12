//
//  RowEditorDateFormatting.swift
//  Tarn
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

// MARK: - Date Picker Kind

enum DatePickerKind: String {
    case none
    case date
    case time
    case dateTime

    var displayedComponents: DatePickerComponents {
        switch self {
        case .date:
            return [.date]
        case .time:
            return [.hourAndMinute]
        case .dateTime:
            return [.date, .hourAndMinute]
        case .none:
            return []
        }
    }
}

// MARK: - Date / Time Formatting

extension RowEditorView {

    func datePickerKind(for dataType: String?) -> DatePickerKind {
        guard let dataType = dataType?.lowercased() else {
            return .none
        }
        if dataType == "date" {
            return .date
        }
        if dataType.contains("timestamp") {
            return .dateTime
        }
        if dataType.contains("time") {
            return .time
        }
        return .none
    }

    func dateValue(for text: String?) -> Date? {
        guard let text = text, !text.isEmpty else {
            return nil
        }
        if let date = iso8601Formatter.date(from: text) {
            return date
        }
        for formatter in parseFormatters {
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    func formatDate(_ date: Date, kind: DatePickerKind) -> String {
        switch kind {
        case .date:
            return dateOnlyFormatter.string(from: date)
        case .time:
            return timeOnlyFormatter.string(from: date)
        case .dateTime:
            return dateTimeFormatter.string(from: date)
        case .none:
            return ""
        }
    }

    // MARK: - Formatters

    var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    var parseFormatters: [DateFormatter] {
        let dateTimeWithZone = DateFormatter()
        dateTimeWithZone.locale = Locale(identifier: "en_US_POSIX")
        dateTimeWithZone.timeZone = TimeZone.current
        dateTimeWithZone.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"

        let dateTime = DateFormatter()
        dateTime.locale = Locale(identifier: "en_US_POSIX")
        dateTime.timeZone = TimeZone.current
        dateTime.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone.current
        dateOnly.dateFormat = "yyyy-MM-dd"

        let timeOnly = DateFormatter()
        timeOnly.locale = Locale(identifier: "en_US_POSIX")
        timeOnly.timeZone = TimeZone.current
        timeOnly.dateFormat = "HH:mm:ss"

        return [dateTimeWithZone, dateTime, dateOnly, timeOnly]
    }

    var dateOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    var timeOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return formatter
    }
}
