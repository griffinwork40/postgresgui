//
//  JSONDetector.swift
//  Tarn
//
//  Pure-logic JSON detection for cell values.
//  Determines whether a string value contains valid JSON
//  and provides pretty-printing for display.
//

import Foundation

enum JSONDetector {

    /// Result of JSON detection on a cell value.
    struct DetectionResult: Equatable, Sendable {
        /// Whether the value is valid JSON.
        let isJSON: Bool

        /// The top-level JSON type (object, array, or nil if not JSON).
        let jsonType: JSONType?

        /// Pretty-printed JSON string, or nil if not valid JSON.
        let prettyPrinted: String?

        static let notJSON = DetectionResult(isJSON: false, jsonType: nil, prettyPrinted: nil)
    }

    /// Top-level JSON container type.
    enum JSONType: String, Sendable {
        case object
        case array
    }

    // MARK: - Quick Check

    /// Fast prefix check — filters out obviously non-JSON strings
    /// before attempting a full parse. Use for cell badge display
    /// where thousands of cells need checking.
    static func mightBeJSON(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty else { return false }

        // Find the first non-whitespace character
        guard let first = value.first(where: { !$0.isWhitespace }) else {
            return false
        }

        guard first == "{" || first == "[" else { return false }

        // Exclude BLOB placeholder strings like "[BLOB: 42 bytes]"
        if first == "[" && value.hasPrefix("[BLOB:") {
            return false
        }

        return true
    }

    // MARK: - Full Detection

    /// Parse and validate a string as JSON. Returns detection result
    /// with type and pretty-printed output on success.
    static func detect(_ value: String?) -> DetectionResult {
        guard let value = value, !value.isEmpty else {
            return .notJSON
        }

        // Quick prefix filter
        guard mightBeJSON(value) else {
            return .notJSON
        }

        guard let data = value.data(using: .utf8) else {
            return .notJSON
        }

        do {
            let parsed = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)

            let jsonType: JSONType
            if parsed is [String: Any] {
                jsonType = .object
            } else if parsed is [Any] {
                jsonType = .array
            } else {
                // Bare scalars (string, number, bool, null) are technically valid
                // JSON fragments but not useful to inspect — treat as non-JSON.
                return .notJSON
            }

            let prettyData = try JSONSerialization.data(
                withJSONObject: parsed,
                options: [.prettyPrinted, .sortedKeys]
            )
            let prettyString = String(data: prettyData, encoding: .utf8)

            return DetectionResult(
                isJSON: true,
                jsonType: jsonType,
                prettyPrinted: prettyString
            )
        } catch {
            return .notJSON
        }
    }

    // MARK: - Cell Display

    /// Short label for a JSON cell badge.
    static func badgeLabel(for result: DetectionResult) -> String? {
        guard result.isJSON, let jsonType = result.jsonType else {
            return nil
        }
        switch jsonType {
        case .object: return "{}"
        case .array: return "[]"
        }
    }
}
