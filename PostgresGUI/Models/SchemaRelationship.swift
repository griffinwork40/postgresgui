//
//  SchemaRelationship.swift
//  PostgresGUI
//
//  Domain models for the Schema Visualization feature.
//  Describes foreign-key relationships between tables and
//  a lightweight snapshot of table metadata.
//

import Foundation

// MARK: - SchemaRelationship

/// A single foreign-key edge: source column → target column.
struct SchemaRelationship: Identifiable, Equatable {
    var id: String { "\(sourceTable).\(sourceColumn)->\(targetTable).\(targetColumn)" }
    let sourceTable: String
    let sourceColumn: String
    let targetTable: String
    let targetColumn: String
}

// MARK: - SchemaTable

/// Lightweight table descriptor used by the schema visualizer.
struct SchemaTable: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let primaryKeys: [String]
    let columnCount: Int
    let rowCount: Int64?

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - SchemaOverview

/// Complete snapshot of a database's schema: tables + FK relationships.
struct SchemaOverview: Equatable {
    let tables: [SchemaTable]
    let relationships: [SchemaRelationship]

    // MARK: - Derived helpers

    /// All FK relationships where `table` is the source (has the FK column).
    func outbound(from table: SchemaTable) -> [SchemaRelationship] {
        relationships.filter { $0.sourceTable == table.name }
    }

    /// All FK relationships where `table` is the target (is referenced).
    func inbound(to table: SchemaTable) -> [SchemaRelationship] {
        relationships.filter { $0.targetTable == table.name }
    }

    /// Whether `table` participates in any FK relationship (source or target).
    func hasRelationships(_ table: SchemaTable) -> Bool {
        relationships.contains {
            $0.sourceTable == table.name || $0.targetTable == table.name
        }
    }
}
