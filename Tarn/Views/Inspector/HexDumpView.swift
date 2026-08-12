//
//  HexDumpView.swift
//  Tarn
//
//  Read-only hex dump display with offset, hex bytes, and ASCII sidebar.
//  Mirrors the layout of a classic hex editor: 16 bytes per row.
//

import SwiftUI

// MARK: - HexDumpView

struct HexDumpView: View {

    /// Maximum bytes to render in the view. Content beyond this is truncated.
    static let maxDisplayBytes = 4096

    let data: Data

    // MARK: - Derived state

    private var displayData: Data {
        data.prefix(Self.maxDisplayBytes)
    }

    private var isTruncated: Bool {
        data.count > Self.maxDisplayBytes
    }

    private var rows: [[UInt8]] {
        stride(from: 0, to: displayData.count, by: 16).map { offset in
            Array(displayData[offset ..< min(offset + 16, displayData.count)])
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isTruncated {
                truncationNote
            }
            hexContent
        }
    }

    // MARK: - Sub-views

    private var truncationNote: some View {
        Text("Showing first \(Self.maxDisplayBytes / 1024) KB of \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
    }

    private var hexContent: some View {
        ScrollView(.vertical) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowBytes in
                    HexRowView(offset: rowIndex * 16, bytes: rowBytes)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - HexRowView

/// A single row in the hex dump: offset | hex bytes | ASCII sidebar.
private struct HexRowView: View {
    let offset: Int
    let bytes: [UInt8]

    var body: some View {
        GridRow {
            // Offset column
            Text(String(format: "%08X", offset))
                .foregroundStyle(.secondary)

            // Hex bytes column — padded to full 16-byte width
            Text(hexString)
                .frame(minWidth: 290, alignment: .leading)

            // ASCII column
            Text(asciiString)
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: - Formatting helpers

    private var hexString: String {
        let hexParts = bytes.map { String(format: "%02X", $0) }
        // Pad to 16 bytes wide so ASCII column stays aligned
        let fullWidth = hexParts + Array(repeating: "  ", count: 16 - bytes.count)
        return fullWidth.joined(separator: " ")
    }

    private var asciiString: String {
        bytes.map { byte -> Character in
            // Printable ASCII range 0x20 – 0x7E; everything else becomes a dot.
            (byte >= 0x20 && byte <= 0x7E) ? Character(UnicodeScalar(byte)) : "."
        }
        .map(String.init)
        .joined()
    }
}
