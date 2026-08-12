//
//  ResultCellView.swift
//  Tarn
//
//  Table cell view for query results. Detects JSON content
//  and displays a clickable badge for inspection.
//

import SwiftUI

struct ResultCellView: View {
    let value: String
    let rawValue: String?
    let onJSONTapped: ((_ rawValue: String) -> Void)?

    /// Cached JSON detection — only runs the prefix check for performance.
    /// Full parse happens on tap.
    private var isLikelyJSON: Bool {
        JSONDetector.mightBeJSON(rawValue)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            if isLikelyJSON {
                jsonBadge
            }
        }
    }

    private var jsonBadge: some View {
        Button {
            guard let raw = rawValue else { return }
            let result = JSONDetector.detect(raw)
            guard result.isJSON else { return }
            onJSONTapped?(raw)
        } label: {
            Text("JSON")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Click to inspect JSON")
    }
}
