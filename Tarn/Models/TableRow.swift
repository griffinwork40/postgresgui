//
//  TableRow.swift
//  Tarn
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct TableRow: Identifiable, Codable {
    let id: UUID
    let values: [String: String?]

    init(id: UUID = UUID(), values: [String: String?]) {
        self.id = id
        self.values = values
    }
}
