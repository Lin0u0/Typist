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

    var errorDescription: String? {
        switch self {
        case .cannotDeleteEntryFile:
            return "The entry file cannot be deleted."
        case .fileAlreadyExists(let name):
            return "A file named \"\(name)\" already exists."
        case .fileNotFound(let name):
            return "File \"\(name)\" not found."
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

    private static var projectsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    static func projectDirectory(for document: TypistDocument) -> URL {
        projectsRoot.appendingPathComponent(document.projectID, isDirectory: true)
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
