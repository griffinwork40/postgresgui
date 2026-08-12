//
//  FTSTableInfo.swift
//  PostgresGUI
//
//  Data model for SQLite Full-Text Search virtual tables.
//

import Foundation

// MARK: - FTSModule

/// The FTS extension module a virtual table was created with.
enum FTSModule: String, CaseIterable, Sendable {
    case fts3
    case fts4
    case fts5

    /// Human-readable display label.
    var displayName: String { rawValue.uppercased() }

    /// Whether this module supports BM25 ranking natively.
    var supportsBM25: Bool { self == .fts5 }

    /// Whether this module supports the `highlight()` auxiliary function.
    var supportsHighlight: Bool { self == .fts5 }
}

// MARK: - FTSTableInfo

/// Metadata for a single FTS virtual table extracted from its CREATE statement.
struct FTSTableInfo: Identifiable, Sendable {
    /// The table name — used as the stable identity.
    let id: String

    /// Table name in the database.
    let name: String

    /// FTS extension module (fts3 / fts4 / fts5).
    let module: FTSModule

    /// Tokenizer specified in the CREATE VIRTUAL TABLE statement, if any.
    /// For fts5 this may be "unicode61", "ascii", "porter", etc.
    let tokenizer: String?

    /// Name of the external content table, if the FTS index is content-backed.
    /// Populated from `content=<tableName>` in the CREATE options.
    let contentTable: String?

    /// The column names that are indexed by this FTS table.
    /// Excludes special FTS options like `content=`, `tokenize=`, etc.
    let indexedColumns: [String]
}

// MARK: - Equatable / Hashable

extension FTSTableInfo: Equatable {
    static func == (lhs: FTSTableInfo, rhs: FTSTableInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension FTSTableInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
