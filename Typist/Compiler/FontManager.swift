//
//  FontManager.swift
//  Typist
//

import Foundation
import os.log

enum FontManager {

    // MARK: - Bundled font

    /// Path to the bundled Source Han Sans SC Regular used as CJK fallback.
    static var bundledCJKFontPath: String? {
        Bundle.main.path(forResource: "SourceHanSansSC-Regular", ofType: "otf")
    }

    // MARK: - Legacy global directory (for migration only)

    private static var legacyFontsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Fonts", isDirectory: true)
    }

    // MARK: - Import / Delete (per-project)

    /// Copy a font file into the project's fonts directory.
    /// Returns the destination file name on success.
    @discardableResult
    static func importFont(from sourceURL: URL, for document: TypistDocument) throws -> String {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        ProjectFileManager.ensureProjectStructure(for: document)
        let fileName = sourceURL.lastPathComponent
        let destination = ProjectFileManager.fontsDirectory(for: document)
            .appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        os_log(.info, "FontManager: imported %{public}@ into project %{public}@", fileName, document.projectID)
        return fileName
    }

    /// Full path for a font file in a document's project, or nil if missing.
    static func fontFilePath(for fileName: String, in document: TypistDocument) -> String? {
        let path = ProjectFileManager.fontsDirectory(for: document)
            .appendingPathComponent(fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Delete a font file from the document's project directory.
    static func deleteFont(fileName: String, from document: TypistDocument) {
        let url = ProjectFileManager.fontsDirectory(for: document)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        os_log(.info, "FontManager: deleted %{public}@ from project %{public}@", fileName, document.projectID)
    }

    // MARK: - Resolve paths for compilation

    /// Returns all font file paths: bundled CJK font + document's custom fonts.
    static func allFontPaths(for document: TypistDocument) -> [String] {
        var paths: [String] = []
        if let bundled = bundledCJKFontPath {
            paths.append(bundled)
        }
        for name in document.fontFileNames {
            if let path = fontFilePath(for: name, in: document) {
                paths.append(path)
            }
        }
        return paths
    }

    // MARK: - Migration from global Fonts/ to per-project

    /// Migrate fonts listed in document.fontFileNames from the legacy global
    /// Documents/Fonts/ directory to the per-project fonts/ directory. Idempotent.
    static func migrateToProject(for document: TypistDocument) {
        let fm = FileManager.default
        let legacyDir = legacyFontsDirectory
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        ProjectFileManager.ensureProjectStructure(for: document)
        let projectFonts = ProjectFileManager.fontsDirectory(for: document)

        for name in document.fontFileNames {
            let src = legacyDir.appendingPathComponent(name)
            let dst = projectFonts.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path),
                  !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
            os_log(.info, "FontManager: migrated %{public}@ to project %{public}@", name, document.projectID)
        }
    }
}
