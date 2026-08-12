//
//  QueryFolder.swift
//  Tarn
//

import Foundation
import SwiftData

@Model
final class QueryFolder: Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \SavedQuery.folder)
    var queries: [SavedQuery]?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
