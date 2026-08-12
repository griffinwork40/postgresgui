//
//  EQPNode.swift
//  PostgresGUI
//
//  Model for a parsed EXPLAIN QUERY PLAN tree node.
//

import SwiftUI

/// A node in the EXPLAIN QUERY PLAN tree.
struct EQPNode: Identifiable {
    let id: Int
    let parentId: Int
    let detail: String
    var children: [EQPNode]

    /// Non-empty children for OutlineGroup (nil = leaf, suppresses disclosure triangle).
    var nonEmptyChildren: [EQPNode]? {
        children.isEmpty ? nil : children
    }

    /// The operation category, derived from the detail text.
    var operation: EQPOperation {
        EQPOperation.classify(detail)
    }

    /// Color for the operation type.
    var operationColor: Color {
        operation.color
    }
}

/// Classified EQP operation types for color coding.
enum EQPOperation {
    case search           // Index lookup — efficient
    case coveringSearch   // Index-only lookup — most efficient
    case scan             // Full table scan — expensive
    case indexScan        // Full index scan — moderate
    case tempBTree        // External sort/group/distinct — expensive
    case subquery         // CO-ROUTINE, MATERIALIZE, SCALAR SUBQUERY
    case compound         // UNION, EXCEPT, INTERSECT
    case other            // Everything else

    var color: Color {
        switch self {
        case .coveringSearch: return .green
        case .search:         return .green.opacity(0.8)
        case .scan:           return .red
        case .indexScan:      return .yellow
        case .tempBTree:      return .red.opacity(0.8)
        case .subquery:       return .blue
        case .compound:       return .blue.opacity(0.8)
        case .other:          return .secondary
        }
    }

    var label: String {
        switch self {
        case .coveringSearch: return "INDEX ONLY"
        case .search:         return "INDEX"
        case .scan:           return "FULL SCAN"
        case .indexScan:      return "INDEX SCAN"
        case .tempBTree:      return "TEMP SORT"
        case .subquery:       return "SUBQUERY"
        case .compound:       return "COMPOUND"
        case .other:          return ""
        }
    }

    static func classify(_ detail: String) -> EQPOperation {
        let upper = detail.uppercased()

        // Order matters: check COVERING before generic SEARCH/SCAN
        if upper.contains("USING COVERING INDEX") {
            return upper.hasPrefix("SEARCH") ? .coveringSearch : .indexScan
        }
        if upper.hasPrefix("SEARCH") {
            return .search
        }
        if upper.hasPrefix("SCAN") && upper.contains("USING INDEX") {
            return .indexScan
        }
        if upper.hasPrefix("SCAN") {
            return .scan
        }
        if upper.contains("USE TEMP B-TREE") {
            return .tempBTree
        }
        if upper.hasPrefix("CO-ROUTINE") || upper.hasPrefix("MATERIALIZE")
            || upper.contains("SCALAR SUBQUERY") || upper.contains("LIST SUBQUERY") {
            return .subquery
        }
        if upper.hasPrefix("COMPOUND") || upper.contains("UNION")
            || upper.contains("EXCEPT") || upper.contains("INTERSECT")
            || upper.hasPrefix("MERGE") {
            return .compound
        }
        return .other
    }
}
