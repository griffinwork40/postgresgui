//
//  TableInfo.swift
//  Tarn
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum TableType: String {
    case regular
    case foreign
    case view
}

struct TableInfo: Identifiable {
    let id: String
    let name: String
    let schema: String
    let tableType: TableType
    var primaryKeyColumns: [String]? = nil
    var columnInfo: [ColumnInfo]? = nil

    init(name: String, schema: String = "public", tableType: TableType = .regular, primaryKeyColumns: [String]? = nil, columnInfo: [ColumnInfo]? = nil) {
        self.id = "\(schema).\(name)"
        self.name = name
        self.schema = schema
        self.tableType = tableType
        self.primaryKeyColumns = primaryKeyColumns
        self.columnInfo = columnInfo
    }

    /// Display name showing schema prefix for non-default schemas.
    /// Both "public" (Postgres) and "main" (SQLite) are treated as default schemas.
    var displayName: String {
        if schema == "public" || schema == "main" {
            return name
        } else {
            return "\(schema).\(name)"
        }
    }
}

// Custom Hashable using only id - prevents List deselection when metadata is updated
extension TableInfo: Equatable {
    static func == (lhs: TableInfo, rhs: TableInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension TableInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
