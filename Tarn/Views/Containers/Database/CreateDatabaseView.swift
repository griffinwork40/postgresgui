//
//  CreateDatabaseView.swift
//  Tarn
//
//  Modal for creating a new database with success/error states.
//

import SwiftUI

struct CreateDatabaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let onConnect: (DatabaseInfo) -> Void

    @State private var databaseName: String = ""
    @State private var isCreating: Bool = false
    @State private var createdDatabase: DatabaseInfo?
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    private var isSuccess: Bool { createdDatabase != nil }
    private var canCreate: Bool { !databaseName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating && !isSuccess }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Database Name")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        TextField("", text: $databaseName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isCreating || isSuccess)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                if canCreate { Task { await createDatabase() } }
                            }
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.subheadline)
                    } else if isSuccess {
                        Label("Database created", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                }
                .padding(20)

                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSuccess ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let database = createdDatabase {
                        Button("Connect") {
                            dismiss()
                            onConnect(database)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Create") { Task { await createDatabase() } }
                            .disabled(!canCreate)
                    }
                }
            }
            .navigationTitle("Create Database")
        }
        .frame(width: 400, height: 180)
        .onAppear { isTextFieldFocused = true }
    }

    private func createDatabase() async {
        let name = databaseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            try await appState.connection.databaseService.createDatabase(name: name)
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
            createdDatabase = appState.connection.databases.first { $0.name == name }
        } catch {
            errorMessage = TarnError.extractDetailedMessage(error)
        }

        isCreating = false
    }
}
