//
//  JSONDocument.swift
//  Tarn
//
//  FileDocument for exporting JSON files
//

import SwiftUI
import UniformTypeIdentifiers

/// Document type for JSON file export
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}
