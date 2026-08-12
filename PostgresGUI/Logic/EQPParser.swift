//
//  EQPParser.swift
//  PostgresGUI
//
//  Parses EXPLAIN QUERY PLAN output into a tree of EQPNode.
//
//  SQLite's EQP returns rows with columns: id, parent, notused, detail.
//  The parser accepts both:
//    1. Tabular query results (rows with "id", "parent", "detail" columns)
//    2. Raw text output (the ASCII-art tree the CLI produces)
//

import Foundation

enum EQPParser {

    // MARK: - Parse from query result rows

    /// Parse EQP rows returned by `EXPLAIN QUERY PLAN` as a tabular query result.
    /// Each row should have "id", "parent", and "detail" keys.
    static func parse(rows: [[String: String]]) -> [EQPNode] {
        guard !rows.isEmpty else { return [] }

        // Build flat node list
        var nodeMap: [Int: EQPNode] = [:]
        var orderedIds: [Int] = []

        for row in rows {
            guard let idStr = row["id"], let id = Int(idStr),
                  let parentStr = row["parent"], let parent = Int(parentStr),
                  let detail = row["detail"] else {
                continue
            }
            let node = EQPNode(id: id, parentId: parent, detail: detail, children: [])
            nodeMap[id] = node
            orderedIds.append(id)
        }

        return assembleTree(nodeMap: &nodeMap, orderedIds: orderedIds)
    }

    /// Parse EQP rows from TableRow format (dictionary-based rows with column names).
    static func parse(
        tableRows: [TableRow],
        columnNames: [String]
    ) -> [EQPNode] {
        // EQP column names (case-insensitive lookup)
        let idKey = columnNames.first { $0.lowercased() == "id" }
        let parentKey = columnNames.first { $0.lowercased() == "parent" }
        let detailKey = columnNames.first { $0.lowercased() == "detail" }

        guard let idKey, let parentKey, let detailKey else { return [] }

        var nodeMap: [Int: EQPNode] = [:]
        var orderedIds: [Int] = []

        for row in tableRows {
            guard let idStr = row.values[idKey] ?? nil,
                  let parentStr = row.values[parentKey] ?? nil,
                  let detail = row.values[detailKey] ?? nil,
                  let id = Int(idStr),
                  let parent = Int(parentStr) else {
                continue
            }

            let node = EQPNode(id: id, parentId: parent, detail: detail, children: [])
            nodeMap[id] = node
            orderedIds.append(id)
        }

        return assembleTree(nodeMap: &nodeMap, orderedIds: orderedIds)
    }

    // MARK: - Parse from text output

    /// Parse the ASCII-art output from the SQLite CLI.
    /// Example:
    /// ```
    /// QUERY PLAN
    /// |--SCAN t1
    /// `--SEARCH t2 USING INDEX idx (a=?)
    /// ```
    static func parseText(_ text: String) -> [EQPNode] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        var nodes: [EQPNode] = []
        var nextId = 1
        // Stack of (depth, nodeId) for parent tracking
        var depthStack: [(depth: Int, id: Int)] = []

        for line in lines {
            // Skip the "QUERY PLAN" header
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "QUERY PLAN" { continue }

            // Calculate depth: count tree-drawing characters
            let (depth, detail) = parseTreeLine(line)

            // Find parent: walk back the stack to find the nearest ancestor
            while let last = depthStack.last, last.depth >= depth {
                depthStack.removeLast()
            }
            let parentId = depthStack.last?.id ?? 0

            let id = nextId
            nextId += 1

            let node = EQPNode(id: id, parentId: parentId, detail: detail, children: [])
            nodes.append(node)
            depthStack.append((depth: depth, id: id))
        }

        // Build tree from flat list
        var nodeMap: [Int: EQPNode] = [:]
        var orderedIds: [Int] = []
        for node in nodes {
            nodeMap[node.id] = node
            orderedIds.append(node.id)
        }

        return assembleTree(nodeMap: &nodeMap, orderedIds: orderedIds)
    }

    // MARK: - Private helpers

    /// Assemble a parent-pointer flat list into a tree.
    private static func assembleTree(
        nodeMap: inout [Int: EQPNode],
        orderedIds: [Int]
    ) -> [EQPNode] {
        // Collect children bottom-up to avoid mutation issues
        var childrenMap: [Int: [Int]] = [:]
        for id in orderedIds {
            guard let node = nodeMap[id] else { continue }
            childrenMap[node.parentId, default: []].append(id)
        }

        // Attach children recursively
        func buildNode(_ id: Int) -> EQPNode? {
            guard var node = nodeMap[id] else { return nil }
            if let childIds = childrenMap[id] {
                node.children = childIds.compactMap { buildNode($0) }
            }
            return node
        }

        // Root nodes: those whose parentId doesn't exist in nodeMap
        let rootIds = orderedIds.filter { id in
            guard let node = nodeMap[id] else { return false }
            return nodeMap[node.parentId] == nil
        }

        return rootIds.compactMap { buildNode($0) }
    }

    /// Parse a single tree-art line into (depth, detail).
    /// Handles: `|--DETAIL`, `` `--DETAIL ``, `|  |--DETAIL`, etc.
    private static func parseTreeLine(_ line: String) -> (depth: Int, detail: String) {
        var depth = 0
        var i = line.startIndex

        while i < line.endIndex {
            let remaining = line[i...]

            if remaining.hasPrefix("|--") || remaining.hasPrefix("`--") {
                // Found a branch marker — detail follows
                let detailStart = line.index(i, offsetBy: 3)
                let detail = String(line[detailStart...]).trimmingCharacters(in: .whitespaces)
                return (depth, detail)
            } else if remaining.hasPrefix("|  ") || remaining.hasPrefix("   ") {
                // Spacer — increase depth
                depth += 1
                i = line.index(i, offsetBy: 3)
            } else {
                // No tree marker — treat entire trimmed line as detail
                let detail = line.trimmingCharacters(in: .whitespaces)
                return (depth, detail)
            }
        }

        return (depth, line.trimmingCharacters(in: .whitespaces))
    }
}
