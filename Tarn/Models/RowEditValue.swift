//
//  RowEditValue.swift
//  Tarn
//
//  Represents an explicit edit value for row updates.
//

import Foundation

enum RowEditValue: Equatable, Hashable {
    case value(String)
    case null
}
