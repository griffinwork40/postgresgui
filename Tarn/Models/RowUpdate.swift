//
//  RowUpdate.swift
//  Tarn
//
//  Created by ghazi on 12/09/24.
//

import Foundation

// Sendable struct to safely pass dictionary through async boundaries
struct RowUpdate: Sendable {
    // Store as array of tuples for reliable async capture
    let entries: [(String, String?)]
    
    var values: [String: String?] {
        Dictionary(uniqueKeysWithValues: entries)
    }
    
    init(values: [String: String?]) {
        // Convert dictionary to array of tuples for reliable async capture
        self.entries = Array(values.map { ($0.key, $0.value) })
    }
    
    // Alternative initializer from entries
    init(entries: [(String, String?)]) {
        self.entries = Array(entries)
    }
}
