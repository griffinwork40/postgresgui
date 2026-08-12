//
//  QueryFolderRowView.swift
//  Tarn
//

import SwiftUI

struct QueryFolderRowView: View {
    let folder: QueryFolder
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            Text(folder.name)
                .lineLimit(1)
            Spacer()
            menuButton
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                DebugLog.print("✏️ [QueryFolderRowView] Rename tapped for folder: \(folder.name)")
                onRename()
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                DebugLog.print("🗑️ [QueryFolderRowView] Delete tapped for folder: \(folder.name)")
                onDelete()
            } label: {
                Label("Delete Folder...", systemImage: "trash")
            }
        }
    }

    private var menuButton: some View {
        Menu {
            Button {
                DebugLog.print("✏️ [QueryFolderRowView] Rename tapped for folder: \(folder.name)")
                onRename()
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                DebugLog.print("🗑️ [QueryFolderRowView] Delete tapped for folder: \(folder.name)")
                onDelete()
            } label: {
                Label("Delete Folder...", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(isButtonHovered ? .primary : .secondary)
                .padding(6)
                .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovered = $0 }
    }
}
