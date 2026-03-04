//
//  ProjectFileManager.swift
//  Typist
//

import Foundation
import os.log

// MARK: - Error type

enum TypistFileError: LocalizedError {
    case cannotDeleteEntryFile
    case fileAlreadyExists(String)
    case fileNotFound(String)
    case invalidFileName(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteEntryFile:
            return "The entry file cannot be deleted."
        case .fileAlreadyExists(let name):
            return "A file named \"\(name)\" already exists."
        case .fileNotFound(let name):
            return "File \"\(name)\" not found."
        case .invalidFileName(let name):
            return "Invalid file name: \"\(name)\"."
        }
    }
}

// MARK: - Project file listing

struct ProjectFiles {
    var typFiles: [String]   // file names relative to project root
    var imageFiles: [String] // file names inside images/
    var fontFiles: [String]  // file names inside fonts/
}

// MARK: - ProjectFileManager

enum ProjectFileManager {

    // MARK: - Directory layout

    private static var documentsURL: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("DocumentDirectory unavailable — this should never happen in a sandboxed app")
        }
        return docs
    }

    static func projectDirectory(for document: TypistDocument) -> URL {
        documentsURL.appendingPathComponent(document.projectID, isDirectory: true)
    }

    static func projectDirectory(folderName: String) -> URL {
        documentsURL.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: - Folder naming

    /// Convert a project title into a safe directory name.
    static func sanitizeFolderName(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafe = CharacterSet(charactersIn: "/:\\*?\"<>|")
        name = name.components(separatedBy: unsafe).joined(separator: "-")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if name.isEmpty { name = "Untitled" }
        return String(name.prefix(200))
    }

    /// Return a folder name that doesn't already exist under Documents/.
    static func uniqueFolderName(for title: String) -> String {
        let fm = FileManager.default
        let base = sanitizeFolderName(title)
        if !fm.fileExists(atPath: documentsURL.appendingPathComponent(base).path) { return base }
        var i = 2
        while fm.fileExists(atPath: documentsURL.appendingPathComponent("\(base) \(i)").path) { i += 1 }
        return "\(base) \(i)"
    }

    // MARK: - Rename

    /// Move the project folder to a new title-derived name. Returns the new projectID.
    @discardableResult
    static func renameProjectDirectory(for document: TypistDocument, to newTitle: String) -> String {
        let newFolderName = uniqueFolderName(for: newTitle)
        let oldDir = projectDirectory(for: document)
        let newDir = documentsURL.appendingPathComponent(newFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }
        return newFolderName
    }

    // MARK: - Filesystem sync

    /// Scan Documents/ and return folder names not yet tracked in the store.
    static func untrackedFolderNames(knownProjectIDs: Set<String>) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let name = url.lastPathComponent
            return knownProjectIDs.contains(name) ? nil : name
        }.sorted()
    }

    // MARK: - Legacy migration

    /// One-time migration: moves Documents/Projects/<UUID>/ → Documents/<title>/ for each document
    /// whose projectID is still a UUID string.
    static func migrateLegacyStructure(documents: [TypistDocument]) {
        let fm = FileManager.default
        let legacyRoot = documentsURL.appendingPathComponent("Projects", isDirectory: true)
        // Quick bail-out if there is nothing from the old layout
        guard fm.fileExists(atPath: legacyRoot.path) else { return }

        for doc in documents {
            guard UUID(uuidString: doc.projectID) != nil else { continue }
            let oldDir = legacyRoot.appendingPathComponent(doc.projectID, isDirectory: true)
            let newFolderName = uniqueFolderName(for: doc.title)
            let newDir = documentsURL.appendingPathComponent(newFolderName, isDirectory: true)
            if fm.fileExists(atPath: oldDir.path) {
                try? fm.moveItem(at: oldDir, to: newDir)
            }
            doc.projectID = newFolderName
            os_log(.info, "ProjectFileManager: migrated %{public}@ → %{public}@", doc.title, newFolderName)
        }

        // Remove the now-empty Projects/ directory
        if let items = try? fm.contentsOfDirectory(atPath: legacyRoot.path), items.isEmpty {
            try? fm.removeItem(at: legacyRoot)
        }
    }

    static func imagesDirectory(for document: TypistDocument) -> URL {
        projectDirectory(for: document)
            .appendingPathComponent(document.imageDirectoryName, isDirectory: true)
    }

    static func fontsDirectory(for document: TypistDocument) -> URL {
        projectDirectory(for: document)
            .appendingPathComponent("fonts", isDirectory: true)
    }

    // MARK: - Lifecycle

    static func ensureProjectStructure(for document: TypistDocument) {
        let fm = FileManager.default
        let dirs = [projectDirectory(for: document),
                    imagesDirectory(for: document),
                    fontsDirectory(for: document)]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func deleteProjectDirectory(for document: TypistDocument) {
        let dir = projectDirectory(for: document)
        try? FileManager.default.removeItem(at: dir)
        os_log(.info, "ProjectFileManager: deleted project dir for %{public}@", document.projectID)
    }

    // MARK: - .typ file URLs

    static func entryFileURL(for document: TypistDocument) -> URL {
        projectDirectory(for: document).appendingPathComponent(document.entryFileName)
    }

    static func typFileURL(named name: String, for document: TypistDocument) -> URL {
        projectDirectory(for: document).appendingPathComponent(name)
    }

    // MARK: - Path validation

    /// Reject names that contain path separators or parent-directory components.
    private static func validateFileName(_ name: String) throws {
        guard !name.isEmpty,
              !name.contains("/"),
              !name.contains("\\"),
              name != "..",
              !name.hasPrefix("../"),
              !name.contains("/../") else {
            throw TypistFileError.invalidFileName(name)
        }
    }

    // MARK: - .typ file CRUD

    static func readTypFile(named name: String, for document: TypistDocument) throws -> String {
        let url = typFileURL(named: name, for: document)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func writeTypFile(named name: String, content: String, for document: TypistDocument) throws {
        let url = typFileURL(named: name, for: document)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func createTypFile(named name: String, for document: TypistDocument) throws {
        try validateFileName(name)
        let url = typFileURL(named: name, for: document)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw TypistFileError.fileAlreadyExists(name)
        }
        try "".write(to: url, atomically: true, encoding: .utf8)
        os_log(.info, "ProjectFileManager: created %{public}@ in %{public}@", name, document.projectID)
    }

    static func deleteTypFile(named name: String, for document: TypistDocument) throws {
        guard name != document.entryFileName else {
            throw TypistFileError.cannotDeleteEntryFile
        }
        try validateFileName(name)
        let url = typFileURL(named: name, for: document)
        try FileManager.default.removeItem(at: url)
        os_log(.info, "ProjectFileManager: deleted %{public}@ from %{public}@", name, document.projectID)
    }

    /// Delete any file by relative path (relative to project root).
    static func deleteProjectFile(relativePath: String, for document: TypistDocument) throws {
        let url = projectDirectory(for: document).appendingPathComponent(relativePath)
        try FileManager.default.removeItem(at: url)
        os_log(.info, "ProjectFileManager: deleted %{public}@", relativePath)
    }

    /// Import an external file into a subdirectory of the project.
    /// `subdir` is relative to the project root (e.g. "images" or "fonts").
    @discardableResult
    static func importFile(from sourceURL: URL, to subdir: String, for document: TypistDocument) throws -> String {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        ensureProjectStructure(for: document)
        let destDir = projectDirectory(for: document).appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileName = sourceURL.lastPathComponent
        let dest = destDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        os_log(.info, "ProjectFileManager: imported %{public}@ into %{public}@/%{public}@", fileName, document.projectID, subdir)
        return "\(subdir)/\(fileName)"
    }

    // MARK: - File listing

    static func listProjectFiles(for document: TypistDocument) -> ProjectFiles {
        let fm = FileManager.default
        let projectDir = projectDirectory(for: document)

        // .typ files in project root
        let typFiles: [String]
        if let items = try? fm.contentsOfDirectory(atPath: projectDir.path) {
            typFiles = items
                .filter { $0.hasSuffix(".typ") }
                .sorted()
        } else {
            typFiles = []
        }

        // image files in images subdir
        let imageFiles: [String]
        let imagesDir = imagesDirectory(for: document)
        if let items = try? fm.contentsOfDirectory(atPath: imagesDir.path) {
            imageFiles = items.filter { !$0.hasPrefix(".") }.sorted()
        } else {
            imageFiles = []
        }

        // font files in fonts subdir
        let fontFiles: [String]
        let fontsDir = fontsDirectory(for: document)
        if let items = try? fm.contentsOfDirectory(atPath: fontsDir.path) {
            fontFiles = items.filter { !$0.hasPrefix(".") }.sorted()
        } else {
            fontFiles = []
        }

        return ProjectFiles(typFiles: typFiles, imageFiles: imageFiles, fontFiles: fontFiles)
    }

    // MARK: - Content migration

    /// One-time migration: write document.content → entry file on disk.
    /// Does nothing if entry file already exists with non-empty content, or if document.content is empty.
    static func migrateContentIfNeeded(for document: TypistDocument) {
        let entryURL = entryFileURL(for: document)
        let fm = FileManager.default

        if fm.fileExists(atPath: entryURL.path) {
            // Entry file already exists — don't overwrite user's work
            return
        }

        // Write content from SwiftData field to disk
        let source = document.content
        try? source.write(to: entryURL, atomically: true, encoding: .utf8)
        os_log(.info, "ProjectFileManager: migrated content to %{public}@ for %{public}@",
               document.entryFileName, document.projectID)
    }

    // MARK: - Image management

    /// Save image data to the project images directory.
    /// Returns the relative path for use in Typst source (e.g. "images/img-A1B2C3D4.jpg").
    @discardableResult
    static func saveImage(data: Data, fileName: String, for document: TypistDocument) throws -> String {
        ensureProjectStructure(for: document)
        let dest = imagesDirectory(for: document).appendingPathComponent(fileName)
        try data.write(to: dest)
        os_log(.info, "ProjectFileManager: saved image %{public}@", fileName)
        return "\(document.imageDirectoryName)/\(fileName)"
    }
}
