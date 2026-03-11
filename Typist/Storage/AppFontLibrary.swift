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

struct AppFontFace: Identifiable, Hashable, Sendable {
    let displayName: String
    let path: String

    var id: String { "\(path)#\(displayName)" }
}

struct AppFontGroup: Identifiable, Sendable {
    let familyName: String
    let isBuiltIn: Bool
    let fileNames: [String]
    let faces: [AppFontFace]
    let count: Int

    var faceNames: [String] { faces.map(\.displayName) }
    var previewPath: String? { faces.first?.path }

    var id: String { familyName }
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

    var groupedItems: [AppFontGroup] {
        var dict: [String: (isBuiltIn: Bool, fileNames: [String], faces: [AppFontFace])] = [:]
        for item in items {
            let key = item.displayName
            let face = AppFontFace(
                displayName: FontManager.typstFaceName(forFontAtPath: item.path) ?? fallbackFaceName(for: item),
                path: item.path
            )
            if var existing = dict[key] {
                if let fn = item.fileName { existing.fileNames.append(fn) }
                existing.faces.append(face)
                dict[key] = existing
            } else {
                let fns: [String] = item.fileName.map { [$0] } ?? []
                dict[key] = (
                    isBuiltIn: item.isBuiltIn,
                    fileNames: fns,
                    faces: [face]
                )
            }
        }
        return dict.map { key, value in
            AppFontGroup(
                familyName: key,
                isBuiltIn: value.isBuiltIn,
                fileNames: value.fileNames,
                faces: value.faces.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                },
                count: max(1, value.faces.count)
            )
        }.sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
    }

    private func fallbackFaceName(for item: AppFontItem) -> String {
        item.fileName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? item.displayName
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
