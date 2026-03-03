//
//  ProjectFileManager.swift
//  Typist
//

import Foundation
import os.log

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
