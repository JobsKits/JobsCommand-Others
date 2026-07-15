//
//  ANSITextSanitizer.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月14日，星期二.
//

import Foundation

enum ANSITextSanitizer {
    static func clean(_ text: String) -> String {
        let patterns = [
            "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            "\u{001B}\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\)",
            "\u{001B}[@-_]"
        ]
        var value = text
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        };return value
    }
}
