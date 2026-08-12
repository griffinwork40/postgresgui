//
//  QueryPlanView.swift
//  Tarn
//
//  Renders an EXPLAIN QUERY PLAN tree with color-coded operations.
//

import SwiftUI

struct QueryPlanView: View {
    let nodes: [EQPNode]

    var body: some View {
        if nodes.isEmpty {
            ContentUnavailableView(
                "No Query Plan",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Run Explain on a query to see its execution plan.")
            )
        } else {
            List {
                OutlineGroup(nodes, id: \.id, children: \.nonEmptyChildren) { node in
                    EQPNodeRow(node: node)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Node Row

private struct EQPNodeRow: View {
    let node: EQPNode

    var body: some View {
        HStack(spacing: 8) {
            // Operation badge
            if !node.operation.label.isEmpty {
                Text(node.operation.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(node.operationColor.opacity(0.2))
                    .foregroundColor(node.operationColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Detail text
            Text(node.detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
