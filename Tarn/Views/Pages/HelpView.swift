//
//  HelpView.swift
//  Tarn
//

import SwiftUI
import AppKit

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.large) {
                    // Support section
                    ShortcutSection(title: "Support") {
                        Button(action: {
                            if let url = URL(string: "https://tarn.com/support") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Help and Support")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Keyboard shortcuts section
                    VStack(alignment: .leading, spacing: Constants.Spacing.small) {
                        Text("Shortcuts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        KeyboardShortcutsContent()
                            .padding()
                            .background(.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Tarn Help")
        }
        .frame(width: 320, height: 340)
    }
}
