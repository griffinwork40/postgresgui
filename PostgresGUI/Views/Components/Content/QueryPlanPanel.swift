//
//  QueryPlanPanel.swift
//  PostgresGUI
//
//  Wraps QueryPlanView with a header bar for dismissal and context.
//

import SwiftUI

struct QueryPlanPanel: View {
    let nodes: [EQPNode]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.secondary)
                Text("Query Plan")
                    .font(.headline)

                Spacer()

                if !nodes.isEmpty {
                    planSummary
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Query Plan")
            }
            .padding(.horizontal, Constants.Spacing.medium)
            .padding(.vertical, Constants.Spacing.small)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Plan tree
            QueryPlanView(nodes: nodes)
        }
    }

    @ViewBuilder
    private var planSummary: some View {
        let stats = summarize(nodes)
        HStack(spacing: 12) {
            if stats.scans > 0 {
                Label("\(stats.scans) scan\(stats.scans == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if stats.searches > 0 {
                Label("\(stats.searches) index", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            if stats.tempSorts > 0 {
                Label("\(stats.tempSorts) sort\(stats.tempSorts == 1 ? "" : "s")", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func summarize(_ nodes: [EQPNode]) -> (scans: Int, searches: Int, tempSorts: Int) {
        var scans = 0, searches = 0, tempSorts = 0
        func walk(_ node: EQPNode) {
            switch node.operation {
            case .scan:           scans += 1
            case .search:         searches += 1
            case .coveringSearch: searches += 1
            case .indexScan:      searches += 1
            case .tempBTree:      tempSorts += 1
            default:              break
            }
            for child in node.children { walk(child) }
        }
        for node in nodes { walk(node) }
        return (scans, searches, tempSorts)
    }
}
