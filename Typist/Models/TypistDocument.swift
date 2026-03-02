//
//  TypistDocument.swift
//  Typist
//

import Foundation
import SwiftData

@Model
final class TypistDocument {
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    init(title: String = "Untitled", content: String = "") {
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
