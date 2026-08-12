//
//  TableColumnRowView.swift
//  Tarn
//

import SwiftUI

// MARK: - Table Column Row View (Sidebar)

/// Compact column display for the table sidebar expansion
struct TableColumnRowView: View {
    let column: ColumnInfo

    /// Simplified data type for display
    private var simplifiedType: String {
        let type = column.dataType.lowercased()

        // Map common PostgreSQL types to simplified names
        if type.hasPrefix("character varying") || type.hasPrefix("varchar") {
            return "varchar"
        } else if type.hasPrefix("character") || type == "char" || type == "bpchar" {
            return "char"
        } else if type == "integer" || type == "int4" {
            return "int"
        } else if type == "bigint" || type == "int8" {
            return "bigint"
        } else if type == "smallint" || type == "int2" {
            return "smallint"
        } else if type == "boolean" || type == "bool" {
            return "bool"
        } else if type.hasPrefix("timestamp") {
            return "timestamp"
        } else if type == "date" {
            return "date"
        } else if type == "time" || type.hasPrefix("time ") {
            return "time"
        } else if type.hasPrefix("numeric") || type.hasPrefix("decimal") {
            return "numeric"
        } else if type == "double precision" || type == "float8" {
            return "double"
        } else if type == "real" || type == "float4" {
            return "float"
        } else if type == "text" {
            return "text"
        } else if type == "uuid" {
            return "uuid"
        } else if type == "json" || type == "jsonb" {
            return type
        } else if type == "bytea" {
            return "bytea"
        } else if type.hasSuffix("[]") {
            // Array types
            let baseType = String(type.dropLast(2))
            return "\(baseType)[]"
        } else {
            // Return as-is for other types
            return column.dataType
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Key icon for PK/FK, dot for others
            if column.isPrimaryKey {
                Image(systemName: "key.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else if column.isForeignKey {
                Image(systemName: "key")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            }

            // Column name (50%)
            Text(column.name)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Data type (50%, right-aligned)
            Text(simplifiedType)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 32)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
    }
}
