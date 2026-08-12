//
//  RowEditorView.swift
//  Tarn
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

// MARK: - Row Editor View

struct RowEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let row: TableRow
    let columnNames: [String]
    let tableName: String
    let columnInfo: [ColumnInfo]
    let primaryKeyColumns: [String]
    @Binding var editedValues: [String: RowEditValue]
    let onSave: () async throws -> Void

    @State private var textValues: [String: String] = [:]
    @State private var nullFlags: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var primaryKeySet: Set<String> {
        Set(primaryKeyColumns)
    }

    private var displayColumnNames: [String] {
        let pkSet = Set(primaryKeyColumns)
        let pkOrdered = primaryKeyColumns.filter { columnNames.contains($0) }
        let nonPkOrdered = columnNames.filter { !pkSet.contains($0) }
        return pkOrdered + nonPkOrdered
    }

    init(
        row: TableRow,
        columnNames: [String],
        tableName: String,
        columnInfo: [ColumnInfo],
        primaryKeyColumns: [String],
        editedValues: Binding<[String: RowEditValue]>,
        onSave: @escaping () async throws -> Void
    ) {
        self.row = row
        self.columnNames = columnNames
        self.tableName = tableName
        self.columnInfo = columnInfo
        self.primaryKeyColumns = primaryKeyColumns
        self._editedValues = editedValues
        self.onSave = onSave

        // Initialize text values and null flags
        var initialTextValues: [String: String] = [:]
        var initialNullFlags: [String: Bool] = [:]

        for columnName in columnNames {
            if let value = row.values[columnName] {
                if let stringValue = value {
                    initialTextValues[columnName] = stringValue
                    initialNullFlags[columnName] = false
                } else {
                    initialTextValues[columnName] = ""
                    initialNullFlags[columnName] = true
                }
            } else {
                // Column doesn't exist in row.values, default to empty
                initialTextValues[columnName] = ""
                initialNullFlags[columnName] = false
            }
        }
        _textValues = State(initialValue: initialTextValues)
        _nullFlags = State(initialValue: initialNullFlags)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayColumnNames, id: \.self) { columnName in
                            formRow(columnName: columnName)
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .navigationTitle("Edit Row")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Error Saving Row", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            if let error = saveError {
                Text(error)
            }
        }
    }

    private func formRow(columnName: String) -> some View {
        let column = columnInfo.first { $0.name == columnName }
        let isNullable = column?.isNullable ?? true
        let isPrimaryKey = primaryKeySet.contains(columnName)
        let dataType = column?.dataType
        let dateFieldKind = datePickerKind(for: dataType)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(columnName)
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                if isPrimaryKey {
                    Text("Primary Key")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isPrimaryKey {
                primaryKeyDisplay(columnName: columnName)
            } else {
                editableField(
                    columnName: columnName,
                    isNullable: isNullable,
                    dateFieldKind: dateFieldKind
                )
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Primary Key Display

    @ViewBuilder
    private func primaryKeyDisplay(columnName: String) -> some View {
        HStack(spacing: 8) {
            Text(textValues[columnName] ?? "")
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Editable Field Router

    @ViewBuilder
    private func editableField(
        columnName: String,
        isNullable: Bool,
        dateFieldKind: DatePickerKind
    ) -> some View {
        let isNull = nullFlags[columnName] ?? false

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if dateFieldKind == .none {
                        singleLineTextField(columnName: columnName, isDisabled: isNull)
                    } else {
                        datePickerField(
                            columnName: columnName,
                            kind: dateFieldKind,
                            isDisabled: isNull
                        )
                    }
                }

                if isNullable {
                    Toggle("NULL", isOn: Binding(
                        get: { nullFlags[columnName] ?? false },
                        set: { isNull in
                            nullFlags[columnName] = isNull
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: - Text Fields

    @ViewBuilder
    private func singleLineTextField(columnName: String, isDisabled: Bool) -> some View {
        TextField("", text: Binding(
            get: { textValues[columnName] ?? "" },
            set: { textValues[columnName] = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .disabled(isDisabled)
        .frame(maxWidth: 380)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.1),
                            Color.clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.multiply)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    private func datePickerField(
        columnName: String,
        kind: DatePickerKind,
        isDisabled: Bool
    ) -> some View {
        DatePicker(
            "",
            selection: Binding(
                get: { dateValue(for: textValues[columnName]) ?? Date() },
                set: { newValue in
                    textValues[columnName] = formatDate(newValue, kind: kind)
                }
            ),
            displayedComponents: kind.displayedComponents
        )
        .datePickerStyle(.field)
        .labelsHidden()
        .disabled(isDisabled)
        .frame(maxWidth: 380, alignment: .leading)
    }

    private func save() async {
        isSaving = true

        DebugLog.print("💾 [RowEditorView.save] START")

        DebugLog.print("  columnNames: \(columnNames)")
        DebugLog.print("  textValues: \(textValues)")
        DebugLog.print("  nullFlags: \(nullFlags)")

        // Combine textValues and nullFlags into editedValues
        var finalValues: [String: RowEditValue] = [:]
        for columnName in columnNames {
            if nullFlags[columnName] ?? false {
                DebugLog.print("    Setting \(columnName) = nil")
                finalValues[columnName] = .null
            } else {
                let value = textValues[columnName] ?? ""
                DebugLog.print("    Setting \(columnName) = '\(value)'")
                finalValues[columnName] = .value(value)
            }
        }

        DebugLog.print("  finalValues count: \(finalValues.count)")
        DebugLog.print("  finalValues keys: \(finalValues.keys)")
        for (key, value) in finalValues {
            DebugLog.print("    \(key): \(String(describing: value))")
        }

        // Store finalValues in the binding so parent can access it
        editedValues = finalValues
        DebugLog.print("  📤 Stored finalValues in editedValues binding")

        do {
            DebugLog.print("  🔵 About to call onSave (no parameters)")
            // Call onSave with no parameters - it will capture editedValues from parent context
            try await onSave()
            DebugLog.print("  ✅ onSave completed")
            dismiss()
        } catch {
            DebugLog.print("  ❌ onSave failed: \(error)")
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}
