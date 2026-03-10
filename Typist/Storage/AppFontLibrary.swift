//
//  AppFontLibrary.swift
//  Typist
//

import Foundation
import Observation

struct AppFontItem: Identifiable, Equatable, Sendable {
    let displayName: String
    let path: String
    let fileName: String?
    let isBuiltIn: Bool

    var id: String { path }
}

@Observable
final class AppFontLibrary {
    private let rootURL: URL?

    private(set) var items: [AppFontItem] = []

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL
        reload()
    }

    var fileNames: [String] {
        items.compactMap { item in
            guard !item.isBuiltIn else { return nil }
            return item.fileName
        }
    }

    var fontPaths: [String] {
        items.map(\.path)
    }

    /// "Empty" intentionally refers to imported App fonts only.
    var isEmpty: Bool {
        fileNames.isEmpty
    }

    func reload() {
        items = FontManager.appFontItems(rootURL: rootURL)
    }

    func importFonts(from urls: [URL]) throws {
        var firstError: Error?

        for url in urls {
            do {
                _ = try FontManager.importAppFont(from: url, rootURL: rootURL)
            } catch {
                firstError = firstError ?? error
            }
        }

        reload()

        if let firstError {
            throw firstError
        }
    }

    func delete(fileName: String) {
        FontManager.deleteAppFont(fileName: fileName, rootURL: rootURL)
        reload()
    }
}
