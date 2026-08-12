//
//  SchemaPicker.swift
//  Tarn
//
//  Schema filter picker for the sidebar.
//

import SwiftUI

/// Schema picker dropdown for filtering tables by schema
struct SchemaPicker: View {
    let schemas: [String]
    let selectedSchema: String?
    let onSelect: (String?) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(selectedSchema ?? "All Schemas")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdownContent
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Dropdown Content

    private var dropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "All Schemas" option
            schemaRow(schema: nil, label: "All Schemas")

            if !schemas.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                // Individual schemas
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(schemas, id: \.self) { schema in
                            schemaRow(schema: schema, label: schema)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 180)
    }

    @ViewBuilder
    private func schemaRow(schema: String?, label: String) -> some View {
        let isSelected = selectedSchema == schema

        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
                .foregroundColor(.accentColor)

            Text(label)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(schema)
            isOpen = false
        }
    }
}
