//
//  BlobAnalyzer.swift
//  PostgresGUI
//
//  Stateless BLOB analysis utility. Detects file type via magic bytes
//  and produces a BlobInspection describing the content.
//

import Foundation

// MARK: - BlobAnalyzer

/// Stateless utility for detecting the content type of raw binary data
/// using magic byte signatures at the start of the payload.
enum BlobAnalyzer {

    // MARK: - Magic Byte Signatures

    /// Known magic byte sequences keyed by their content type.
    /// Ordered from most-specific (longest prefix) to least-specific.
    private static let signatures: [(bytes: [UInt8], type: BlobContentType)] = [
        // SQLite database — 16-byte magic string "SQLite format 3\0"
        (
            [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
             0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00],
            .sqlite
        ),
        // PDF — "%PDF"
        ([0x25, 0x50, 0x44, 0x46], .pdf),
        // ZIP — "PK\x03\x04"
        ([0x50, 0x4B, 0x03, 0x04], .zip),
        // PNG — "\x89PNG"
        ([0x89, 0x50, 0x4E, 0x47], .image(.png)),
        // GIF — "GIF8"
        ([0x47, 0x49, 0x46, 0x38], .image(.gif)),
        // JPEG — FF D8 FF
        ([0xFF, 0xD8, 0xFF], .image(.jpeg)),
    ]

    // MARK: - Public API

    /// Analyze raw data and return a typed inspection result.
    ///
    /// - Parameter data: The raw BLOB payload.
    /// - Returns: A `BlobInspection` describing the content type and size.
    static func analyze(_ data: Data) -> BlobInspection {
        let contentType = detectContentType(data)
        return BlobInspection(
            data: data,
            contentType: contentType,
            size: data.count
        )
    }

    // MARK: - Internal Detection

    /// Match data against known magic byte signatures.
    /// Returns `.unknown` if no signature matches.
    static func detectContentType(_ data: Data) -> BlobContentType {
        guard !data.isEmpty else { return .unknown }

        for signature in signatures {
            if hasPrefix(data, bytes: signature.bytes) {
                return signature.type
            }
        }
        return .unknown
    }

    /// Returns true when `data` starts with the given byte sequence.
    private static func hasPrefix(_ data: Data, bytes: [UInt8]) -> Bool {
        guard data.count >= bytes.count else { return false }
        return data.prefix(bytes.count).elementsEqual(bytes)
    }
}
