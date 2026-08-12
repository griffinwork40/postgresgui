//
//  EmptyQueryResultsView.swift
//  Tarn
//
//  Empty state view displayed when a query returns no rows.
//

import SwiftUI

struct EmptyQueryResultsView: View {
    var hasExecutedQuery: Bool = true

    var body: some View {
        Text(hasExecutedQuery ? "No rows found" : "Run a query to see results")
            .foregroundStyle(.secondary)
    }
}
