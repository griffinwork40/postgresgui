//
//  JSONDetectorTests.swift
//  TarnTests
//
//  Tests for JSONDetector — JSON detection in cell values.
//

import XCTest
@testable import Tarn

final class JSONDetectorTests: XCTestCase {

    // MARK: - mightBeJSON (Quick Check)

    func testMightBeJSON_nilReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON(nil))
    }

    func testMightBeJSON_emptyStringReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON(""))
    }

    func testMightBeJSON_plainTextReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON("hello world"))
    }

    func testMightBeJSON_numberStringReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON("42"))
    }

    func testMightBeJSON_objectPrefixReturns_true() {
        XCTAssertTrue(JSONDetector.mightBeJSON("{\"key\": \"value\"}"))
    }

    func testMightBeJSON_arrayPrefixReturns_true() {
        XCTAssertTrue(JSONDetector.mightBeJSON("[1, 2, 3]"))
    }

    func testMightBeJSON_leadingWhitespaceObjectReturns_true() {
        XCTAssertTrue(JSONDetector.mightBeJSON("  \n  {\"key\": 1}"))
    }

    func testMightBeJSON_leadingWhitespaceArrayReturns_true() {
        XCTAssertTrue(JSONDetector.mightBeJSON("  [1]"))
    }

    func testMightBeJSON_blobPlaceholderReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON("[BLOB: 42 bytes]"))
    }

    func testMightBeJSON_blobPlaceholderVariantsReturn_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON("[BLOB: 0 bytes]"))
        XCTAssertFalse(JSONDetector.mightBeJSON("[BLOB: 1234567 bytes]"))
    }

    func testMightBeJSON_allWhitespaceReturns_false() {
        XCTAssertFalse(JSONDetector.mightBeJSON("   \n\t  "))
    }

    // MARK: - detect (Full Parse)

    func testDetect_nilReturns_notJSON() {
        let result = JSONDetector.detect(nil)
        XCTAssertFalse(result.isJSON)
        XCTAssertNil(result.jsonType)
        XCTAssertNil(result.prettyPrinted)
    }

    func testDetect_emptyStringReturns_notJSON() {
        let result = JSONDetector.detect("")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_plainTextReturns_notJSON() {
        let result = JSONDetector.detect("just a string")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_validObjectReturns_JSONObject() {
        let input = #"{"name": "test", "value": 42}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
        XCTAssertNotNil(result.prettyPrinted)
        XCTAssertTrue(result.prettyPrinted!.contains("\"name\""))
        XCTAssertTrue(result.prettyPrinted!.contains("\"test\""))
    }

    func testDetect_validArrayReturns_JSONArray() {
        let input = "[1, 2, 3]"
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .array)
        XCTAssertNotNil(result.prettyPrinted)
    }

    func testDetect_nestedObjectReturns_JSON() {
        let input = #"{"user": {"name": "Alice", "scores": [10, 20]}}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
        XCTAssertNotNil(result.prettyPrinted)
    }

    func testDetect_emptyObjectReturns_JSON() {
        let result = JSONDetector.detect("{}")
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
    }

    func testDetect_emptyArrayReturns_JSON() {
        let result = JSONDetector.detect("[]")
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .array)
    }

    func testDetect_invalidJSONWithBracesReturns_notJSON() {
        let result = JSONDetector.detect("{not valid json}")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_invalidJSONWithBracketsReturns_notJSON() {
        let result = JSONDetector.detect("[not, valid]")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_bareScalarStringReturns_notJSON() {
        // A bare JSON string is technically valid JSON but not useful to inspect
        let result = JSONDetector.detect("\"just a string\"")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_bareNumberReturns_notJSON() {
        let result = JSONDetector.detect("42")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_bareBoolReturns_notJSON() {
        let result = JSONDetector.detect("true")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_bareNullReturns_notJSON() {
        let result = JSONDetector.detect("null")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_prettyPrintsSortedKeys() {
        let input = #"{"z": 1, "a": 2, "m": 3}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        guard let pretty = result.prettyPrinted else {
            XCTFail("Expected pretty-printed output")
            return
        }
        // Sorted keys: a should appear before m, m before z
        let aRange = pretty.range(of: "\"a\"")!
        let mRange = pretty.range(of: "\"m\"")!
        let zRange = pretty.range(of: "\"z\"")!
        XCTAssertTrue(aRange.lowerBound < mRange.lowerBound)
        XCTAssertTrue(mRange.lowerBound < zRange.lowerBound)
    }

    func testDetect_arrayOfObjectsReturns_JSON() {
        let input = #"[{"id": 1}, {"id": 2}]"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .array)
    }

    func testDetect_unicodeContentReturns_JSON() {
        let input = #"{"emoji": "🎉", "name": "Ñoño"}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
    }

    func testDetect_largeNumbersPreserved() {
        let input = #"{"bigint": 9223372036854775807}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertNotNil(result.prettyPrinted)
    }

    func testDetect_nullValuesInObjectReturns_JSON() {
        let input = #"{"key": null, "other": "value"}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
    }

    // MARK: - badgeLabel

    func testBadgeLabel_objectReturns_braces() {
        let result = JSONDetector.detect("{\"a\": 1}")
        XCTAssertEqual(JSONDetector.badgeLabel(for: result), "{}")
    }

    func testBadgeLabel_arrayReturns_brackets() {
        let result = JSONDetector.detect("[1, 2]")
        XCTAssertEqual(JSONDetector.badgeLabel(for: result), "[]")
    }

    func testBadgeLabel_notJSONReturns_nil() {
        let result = JSONDetector.detect("plain text")
        XCTAssertNil(JSONDetector.badgeLabel(for: result))
    }

    // MARK: - Edge Cases

    func testDetect_truncatedJSONReturns_notJSON() {
        // Simulates a value truncated by TableBrowseResultCompactor
        let input = #"{"key": "very long val... [truncated]"#
        let result = JSONDetector.detect(input)
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_blobPlaceholderReturns_notJSON() {
        let result = JSONDetector.detect("[BLOB: 42 bytes]")
        XCTAssertFalse(result.isJSON)
    }

    func testDetect_whitespaceAroundValidJSONReturns_JSON() {
        let input = "  \n  {\"key\": \"value\"}  \n  "
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
    }

    func testDetect_deeplyNestedJSONReturns_JSON() {
        let input = #"{"a": {"b": {"c": {"d": [1, 2, 3]}}}}"#
        let result = JSONDetector.detect(input)
        XCTAssertTrue(result.isJSON)
        XCTAssertEqual(result.jsonType, .object)
    }

    func testDetect_equatableConformance() {
        let a = JSONDetector.detect("{\"x\": 1}")
        let b = JSONDetector.detect("{\"x\": 1}")
        XCTAssertEqual(a, b)
    }

    func testDetect_notJSONEquatableConformance() {
        let a = JSONDetector.DetectionResult.notJSON
        let b = JSONDetector.detect("nope")
        XCTAssertEqual(a, b)
    }
}
