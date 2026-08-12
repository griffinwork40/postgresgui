//
//  TableGrouping.swift
//  Tarn
//
//  Pure functions for grouping tables.
//

import Foundation

/// A group of tables belonging to the same schema
struct SchemaGroup: Identifiable {
    let name: String
    let tables: [TableInfo]

    var id: String { name }
    var tableCount: Int { tables.count }
}

/// Groups tables by their schema, sorted alphabetically with "public" first
/// - Parameter tables: Array of tables to group
/// - Returns: Array of schema groups, sorted with "public" first, then alphabetically
func groupTablesBySchema(_ tables: [TableInfo]) -> [SchemaGroup] {
    Dictionary(grouping: tables, by: \.schema)
        .map { SchemaGroup(name: $0.key, tables: $0.value.sorted { $0.name < $1.name }) }
        .sorted { lhs, rhs in
            // "public" schema always comes first
            if lhs.name == "public" { return true }
            if rhs.name == "public" { return false }
            return lhs.name < rhs.name
        }
}
