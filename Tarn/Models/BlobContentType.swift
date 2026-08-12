//
//  BlobContentType.swift
//  Tarn
//
//  Data model for BLOB content type detection results.
//

import Foundation

// MARK: - BlobContentType

/// The detected format of a raw BLOB value.
enum BlobContentType: Equatable {
    case image(ImageFormat)
    case pdf
    case zip
    case sqlite
    case unknown

    // MARK: - ImageFormat

    enum ImageFormat: String {
        case jpeg
        case png
        case gif
    }

    // MARK: - Display Helpers

    /// Short badge label for UI display.
    var badgeLabel: String {
        switch self {
        case .image(let fmt):
            return fmt.rawValue.uppercased()
        case .pdf:
            return "PDF"
        case .zip:
            return "ZIP"
        case .sqlite:
            return "SQLite"
        case .unknown:
            return "BIN"
        }
    }

    /// System image name for this content type.
    var systemImage: String {
        switch self {
        case .image:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .zip:
            return "archivebox"
        case .sqlite:
            return "cylinder"
        case .unknown:
            return "doc.badge.gearshape"
        }
    }

    /// File extension to use when saving.
    var fileExtension: String {
        switch self {
        case .image(let fmt):
            return fmt.rawValue
        case .pdf:
            return "pdf"
        case .zip:
            return "zip"
        case .sqlite:
            return "sqlite"
        case .unknown:
            return "bin"
        }
    }
}

// MARK: - BlobInspection

/// The result of analyzing a raw BLOB value.
struct BlobInspection {
    /// The raw data from the database.
    let data: Data

    /// Detected content type from magic byte analysis.
    let contentType: BlobContentType

    /// Size in bytes.
    let size: Int

    /// Human-readable size string (e.g. "4.2 KB").
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
