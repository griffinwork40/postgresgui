//
//  MutationToastView.swift
//  Tarn
//
//  Created by Claude on 12/25/25.
//

import SwiftUI

struct MutationToastData: Equatable {
    let title: String
    let tableName: String?
    let queryType: QueryType

    var showViewTableButton: Bool {
        tableName != nil && queryType != .dropTable
    }
}

struct MutationToastView: View {
    let data: MutationToastData
    let onViewTable: () -> Void
    let onDismiss: () -> Void

    @State private var isAppearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)

                Text(data.title)
                    .font(.headline)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if data.showViewTableButton {
                Button {
                    onViewTable()
                } label: {
                    Text("View Table")
                        .font(.subheadline)
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .offset(x: isAppearing ? 0 : 50)
        .opacity(isAppearing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isAppearing = true
            }
        }
    }
}
