//
//  ExportManager.swift
//  Typist
//

import Foundation
import UIKit

enum ExportManager {

    /// Compile document to PDF data on a background thread.
    /// Reads source from the entry file on disk.
    static func compilePDF(for document: TypistDocument) async -> Result<Data, TypstBridgeError> {
        let source = (try? ProjectFileManager.readTypFile(named: document.entryFileName, for: document)) ?? document.content
        let fontPaths = FontManager.allFontPaths(for: document)
        let rootDir = ProjectFileManager.projectDirectory(for: document).path

        return await Task.detached {
            TypstBridge.compile(source: source, fontPaths: fontPaths, rootDir: rootDir)
        }.value
    }

    /// Write PDF data to a temporary file and return its URL.
    static func temporaryPDFURL(data: Data, title: String) throws -> URL {
        let sanitized = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized).pdf")
        try data.write(to: url)
        return url
    }

    /// Write .typ source to a temporary file and return its URL.
    /// Reads source from the entry file on disk.
    static func temporaryTypURL(for document: TypistDocument) throws -> URL {
        let sanitized = document.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized).typ")
        let source = (try? ProjectFileManager.readTypFile(named: document.entryFileName, for: document)) ?? document.content
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Present the system print dialog for PDF data.
    static func printPDF(data: Data, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true)
    }
}
