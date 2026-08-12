//
//  TimeInterval+Extensions.swift
//  Tarn
//
//  Extension for TimeInterval to provide convenient conversions
//

import Foundation

extension TimeInterval {
    /// Convert TimeInterval to nanoseconds for Task.sleep
    var nanoseconds: UInt64 {
        UInt64(self * 1_000_000_000)
    }
    
    /// Convert TimeInterval to milliseconds
    var milliseconds: UInt64 {
        UInt64(self * 1_000)
    }
}
