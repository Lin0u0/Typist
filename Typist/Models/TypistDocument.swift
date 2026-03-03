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
    var fontFileNames: [String] = []
    var projectID: String = UUID().uuidString
    var imageInsertMode: String = "image"
    var imageDirectoryName: String = "images"

    init(title: String = "Untitled", content: String = "") {
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.fontFileNames = []
        self.projectID = UUID().uuidString
    }

    var imageInsertionTemplate: String {
        switch imageInsertMode {
        case "figure":
            return "#figure(image(\"%@\"), caption: [])"
        default:
            return "#image(\"%@\")"
        }
    }
}
