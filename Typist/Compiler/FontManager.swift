//
//  FontManager.swift
//  Typist
//

import Foundation
import os.log

enum FontManager {

    // MARK: - Directories

    /// App Documents/Fonts/ — stores user-imported font files.
    static var fontsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Bundled font

    /// Path to the bundled Source Han Sans SC Regular used as CJK fallback.
    static var bundledCJKFontPath: String? {
        Bundle.main.path(forResource: "SourceHanSansSC-Regular", ofType: "otf")
    }

    // MARK: - Import / Delete

    /// Copy a font file from a Document Picker URL into the Fonts directory.
    /// Returns the destination file name on success.
    @discardableResult
    static func importFont(from sourceURL: URL) throws -> String {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        let destination = fontsDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        os_log(.info, "FontManager: imported %{public}@", fileName)
        return fileName
    }

    /// Full path for a user-imported font file name, or nil if it doesn't exist.
    static func fontFilePath(for fileName: String) -> String? {
        let path = fontsDirectory.appendingPathComponent(fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Delete a user-imported font file.
    static func deleteFont(fileName: String) {
        let url = fontsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        os_log(.info, "FontManager: deleted %{public}@", fileName)
    }

    // MARK: - Resolve paths for compilation

    /// Returns all font file paths for a document: bundled CJK font + document's custom fonts.
    static func allFontPaths(for document: TypistDocument) -> [String] {
        var paths: [String] = []
        if let bundled = bundledCJKFontPath {
            paths.append(bundled)
        }
        for name in document.fontFileNames {
            if let path = fontFilePath(for: name) {
                paths.append(path)
            }
        }
        return paths
    }
}
