//
//  BlobAnalyzerTests.swift
//  PostgresGUITests
//
//  Tests for BlobAnalyzer and BlobContentType — magic byte detection and
//  content type metadata.
//

import XCTest
@testable import PostgresGUI

final class BlobAnalyzerTests: XCTestCase {

    // MARK: - Helpers

    private func data(_ bytes: [UInt8]) -> Data { Data(bytes) }

    // Padding that won't match any signature, used to extend short magic headers.
    private let padding: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]

    // MARK: - JPEG Detection (FF D8 FF)

    func testDetectContentType_jpegMagicBytes_returnsJPEG() {
        let jpeg = data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        XCTAssertEqual(BlobAnalyzer.detectContentType(jpeg), .image(.jpeg))
    }

    func testDetectContentType_jpegExactThreeBytes_returnsJPEG() {
        let jpeg = data([0xFF, 0xD8, 0xFF])
        XCTAssertEqual(BlobAnalyzer.detectContentType(jpeg), .image(.jpeg))
    }

    func testDetectContentType_jpegWithTrailingData_returnsJPEG() {
        let jpeg = data([0xFF, 0xD8, 0xFF] + padding)
        XCTAssertEqual(BlobAnalyzer.detectContentType(jpeg), .image(.jpeg))
    }

    func testDetectContentType_truncatedJPEG_returnsUnknown() {
        let truncated = data([0xFF, 0xD8])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    func testDetectContentType_jpegFirstByteOnly_returnsUnknown() {
        let truncated = data([0xFF])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    // MARK: - PNG Detection (89 50 4E 47)

    func testDetectContentType_pngMagicBytes_returnsPNG() {
        let png = data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(BlobAnalyzer.detectContentType(png), .image(.png))
    }

    func testDetectContentType_pngExactFourBytes_returnsPNG() {
        let png = data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(BlobAnalyzer.detectContentType(png), .image(.png))
    }

    func testDetectContentType_pngWithTrailingData_returnsPNG() {
        let png = data([0x89, 0x50, 0x4E, 0x47] + padding)
        XCTAssertEqual(BlobAnalyzer.detectContentType(png), .image(.png))
    }

    func testDetectContentType_truncatedPNG_returnsUnknown() {
        let truncated = data([0x89, 0x50, 0x4E])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    // MARK: - GIF Detection (47 49 46 38)

    func testDetectContentType_gifMagicBytes_returnsGIF() {
        // "GIF89a" header
        let gif = data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        XCTAssertEqual(BlobAnalyzer.detectContentType(gif), .image(.gif))
    }

    func testDetectContentType_gifExactFourBytes_returnsGIF() {
        let gif = data([0x47, 0x49, 0x46, 0x38])
        XCTAssertEqual(BlobAnalyzer.detectContentType(gif), .image(.gif))
    }

    func testDetectContentType_gif87aVariant_returnsGIF() {
        // "GIF87a" also starts with "GIF8"
        let gif = data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
        XCTAssertEqual(BlobAnalyzer.detectContentType(gif), .image(.gif))
    }

    func testDetectContentType_truncatedGIF_returnsUnknown() {
        let truncated = data([0x47, 0x49, 0x46])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    // MARK: - PDF Detection (25 50 44 46)

    func testDetectContentType_pdfMagicBytes_returnsPDF() {
        // "%PDF-1.7"
        let pdf = data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37])
        XCTAssertEqual(BlobAnalyzer.detectContentType(pdf), .pdf)
    }

    func testDetectContentType_pdfExactFourBytes_returnsPDF() {
        let pdf = data([0x25, 0x50, 0x44, 0x46])
        XCTAssertEqual(BlobAnalyzer.detectContentType(pdf), .pdf)
    }

    func testDetectContentType_pdfWithTrailingData_returnsPDF() {
        let pdf = data([0x25, 0x50, 0x44, 0x46] + padding)
        XCTAssertEqual(BlobAnalyzer.detectContentType(pdf), .pdf)
    }

    func testDetectContentType_truncatedPDF_returnsUnknown() {
        let truncated = data([0x25, 0x50, 0x44])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    // MARK: - ZIP Detection (50 4B 03 04)

    func testDetectContentType_zipMagicBytes_returnsZIP() {
        let zip = data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
        XCTAssertEqual(BlobAnalyzer.detectContentType(zip), .zip)
    }

    func testDetectContentType_zipExactFourBytes_returnsZIP() {
        let zip = data([0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(BlobAnalyzer.detectContentType(zip), .zip)
    }

    func testDetectContentType_zipWithTrailingData_returnsZIP() {
        let zip = data([0x50, 0x4B, 0x03, 0x04] + padding)
        XCTAssertEqual(BlobAnalyzer.detectContentType(zip), .zip)
    }

    func testDetectContentType_truncatedZIP_returnsUnknown() {
        let truncated = data([0x50, 0x4B, 0x03])
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    // MARK: - SQLite Detection (16-byte header)

    private let sqliteHeader: [UInt8] = [
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,  // "SQLite f"
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00   // "ormat 3\0"
    ]

    func testDetectContentType_sqliteMagicHeader_returnsSQLite() {
        let sqlite = data(sqliteHeader)
        XCTAssertEqual(BlobAnalyzer.detectContentType(sqlite), .sqlite)
    }

    func testDetectContentType_sqliteWithTrailingData_returnsSQLite() {
        let sqlite = data(sqliteHeader + padding)
        XCTAssertEqual(BlobAnalyzer.detectContentType(sqlite), .sqlite)
    }

    func testDetectContentType_sqliteHeaderMinus1Byte_returnsUnknown() {
        // 15 bytes — one short of the full 16-byte magic string
        let truncated = data(Array(sqliteHeader.dropLast()))
        XCTAssertEqual(BlobAnalyzer.detectContentType(truncated), .unknown)
    }

    func testDetectContentType_sqliteNullTerminatorMissing_returnsUnknown() {
        // Replace trailing 0x00 with 0x01 — no longer a valid SQLite header
        var mutated = sqliteHeader
        mutated[15] = 0x01
        XCTAssertEqual(BlobAnalyzer.detectContentType(data(mutated)), .unknown)
    }

    func testDetectContentType_plainTextSQLiteString_returnsUnknown() {
        // "SQLite format 3" as a Swift string rounds to UTF-8 without the NUL byte
        let str = "SQLite format 3"
        let strData = str.data(using: .utf8)!
        // 15 bytes — still one short; must not accidentally match
        XCTAssertEqual(BlobAnalyzer.detectContentType(strData), .unknown)
    }

    // MARK: - Unknown / Random Binary Data

    func testDetectContentType_randomBytes_returnsUnknown() {
        let random = data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        XCTAssertEqual(BlobAnalyzer.detectContentType(random), .unknown)
    }

    func testDetectContentType_allZeroBytes_returnsUnknown() {
        let zeros = data([UInt8](repeating: 0x00, count: 16))
        XCTAssertEqual(BlobAnalyzer.detectContentType(zeros), .unknown)
    }

    func testDetectContentType_singleByte_returnsUnknown() {
        XCTAssertEqual(BlobAnalyzer.detectContentType(data([0x42])), .unknown)
    }

    func testDetectContentType_validUTF8Text_returnsUnknown() {
        let text = "Hello, world!".data(using: .utf8)!
        XCTAssertEqual(BlobAnalyzer.detectContentType(text), .unknown)
    }

    // MARK: - Empty Data

    func testDetectContentType_emptyData_returnsUnknown() {
        XCTAssertEqual(BlobAnalyzer.detectContentType(Data()), .unknown)
    }

    func testAnalyze_emptyData_returnsUnknownInspection() {
        let inspection = BlobAnalyzer.analyze(Data())
        XCTAssertEqual(inspection.contentType, .unknown)
        XCTAssertEqual(inspection.size, 0)
    }

    // MARK: - BlobContentType Badge Labels

    func testBadgeLabel_jpeg_returnsJPEG() {
        XCTAssertEqual(BlobContentType.image(.jpeg).badgeLabel, "JPEG")
    }

    func testBadgeLabel_png_returnsPNG() {
        XCTAssertEqual(BlobContentType.image(.png).badgeLabel, "PNG")
    }

    func testBadgeLabel_gif_returnsGIF() {
        XCTAssertEqual(BlobContentType.image(.gif).badgeLabel, "GIF")
    }

    func testBadgeLabel_pdf_returnsPDF() {
        XCTAssertEqual(BlobContentType.pdf.badgeLabel, "PDF")
    }

    func testBadgeLabel_zip_returnsZIP() {
        XCTAssertEqual(BlobContentType.zip.badgeLabel, "ZIP")
    }

    func testBadgeLabel_sqlite_returnsSQLite() {
        XCTAssertEqual(BlobContentType.sqlite.badgeLabel, "SQLite")
    }

    func testBadgeLabel_unknown_returnsBIN() {
        XCTAssertEqual(BlobContentType.unknown.badgeLabel, "BIN")
    }

    // MARK: - BlobContentType File Extensions

    func testFileExtension_jpeg_returnsJpeg() {
        XCTAssertEqual(BlobContentType.image(.jpeg).fileExtension, "jpeg")
    }

    func testFileExtension_png_returnsPng() {
        XCTAssertEqual(BlobContentType.image(.png).fileExtension, "png")
    }

    func testFileExtension_gif_returnsGif() {
        XCTAssertEqual(BlobContentType.image(.gif).fileExtension, "gif")
    }

    func testFileExtension_pdf_returnsPdf() {
        XCTAssertEqual(BlobContentType.pdf.fileExtension, "pdf")
    }

    func testFileExtension_zip_returnsZip() {
        XCTAssertEqual(BlobContentType.zip.fileExtension, "zip")
    }

    func testFileExtension_sqlite_returnsSqlite() {
        XCTAssertEqual(BlobContentType.sqlite.fileExtension, "sqlite")
    }

    func testFileExtension_unknown_returnsBin() {
        XCTAssertEqual(BlobContentType.unknown.fileExtension, "bin")
    }

    // MARK: - BlobInspection (analyze() wrapper)

    func testAnalyze_jpegData_returnsCorrectInspection() {
        let bytes = data([0xFF, 0xD8, 0xFF, 0xE0] + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .image(.jpeg))
        XCTAssertEqual(inspection.size, bytes.count)
        XCTAssertTrue(inspection.data.elementsEqual(bytes))
    }

    func testAnalyze_pngData_returnsCorrectInspection() {
        let bytes = data([0x89, 0x50, 0x4E, 0x47] + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .image(.png))
        XCTAssertEqual(inspection.size, bytes.count)
    }

    func testAnalyze_pdfData_returnsCorrectInspection() {
        let bytes = data([0x25, 0x50, 0x44, 0x46] + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .pdf)
        XCTAssertEqual(inspection.size, bytes.count)
    }

    func testAnalyze_zipData_returnsCorrectInspection() {
        let bytes = data([0x50, 0x4B, 0x03, 0x04] + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .zip)
        XCTAssertEqual(inspection.size, bytes.count)
    }

    func testAnalyze_sqliteData_returnsCorrectInspection() {
        let bytes = data(sqliteHeader + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .sqlite)
        XCTAssertEqual(inspection.size, bytes.count)
    }

    func testAnalyze_unknownData_returnsCorrectInspection() {
        let bytes = data([0xDE, 0xAD, 0xBE, 0xEF])
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.contentType, .unknown)
        XCTAssertEqual(inspection.size, 4)
    }

    func testAnalyze_sizeMatchesDataCount() {
        // Verify size is always data.count, not a computed alternative
        let bytes = data([UInt8](repeating: 0xAB, count: 128))
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertEqual(inspection.size, 128)
    }

    func testAnalyze_formattedSizeIsNonEmpty() {
        let bytes = data([0xFF, 0xD8, 0xFF] + padding)
        let inspection = BlobAnalyzer.analyze(bytes)
        XCTAssertFalse(inspection.formattedSize.isEmpty)
    }

    // MARK: - Equatable Conformance

    func testEquatable_sameImageFormat_isEqual() {
        XCTAssertEqual(BlobContentType.image(.jpeg), BlobContentType.image(.jpeg))
        XCTAssertEqual(BlobContentType.image(.png), BlobContentType.image(.png))
        XCTAssertEqual(BlobContentType.image(.gif), BlobContentType.image(.gif))
    }

    func testEquatable_differentImageFormats_notEqual() {
        XCTAssertNotEqual(BlobContentType.image(.jpeg), BlobContentType.image(.png))
        XCTAssertNotEqual(BlobContentType.image(.png), BlobContentType.image(.gif))
    }

    func testEquatable_differentTopLevelTypes_notEqual() {
        XCTAssertNotEqual(BlobContentType.pdf, BlobContentType.zip)
        XCTAssertNotEqual(BlobContentType.sqlite, BlobContentType.unknown)
        XCTAssertNotEqual(BlobContentType.image(.jpeg), BlobContentType.pdf)
    }
}
