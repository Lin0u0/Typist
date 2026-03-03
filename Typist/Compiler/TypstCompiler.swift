//
//  TypstCompiler.swift
//  Typist
//
//  Debounced compile pipeline: source → Rust FFI → PDFKit document.
//

import Foundation
import PDFKit
import Observation

@Observable
final class TypstCompiler {
    private(set) var pdfDocument: PDFDocument?
    private(set) var errorMessage: String?
    private(set) var isCompiling: Bool = false

    private var compileTask: Task<Void, Never>?

    /// Schedule a compilation 500 ms after the last call.
    /// Cancels any in-flight compile task before scheduling a new one.
    func compile(source: String, fontPaths: [String]) {
        compileTask?.cancel()
        compileTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return // cancelled — do nothing
            }

            await MainActor.run { self.isCompiling = true }

            let result = await Task.detached(priority: .userInitiated) {
                TypstBridge.compile(source: source, fontPaths: fontPaths)
            }.value

            await MainActor.run {
                self.isCompiling = false
                switch result {
                case .success(let pdfData):
                    self.pdfDocument = PDFDocument(data: pdfData)
                    self.errorMessage = nil
                case .failure(let error):
                    // Keep the last successful PDF visible; only update the error banner.
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Cancel any in-flight compilation (e.g. when document is closed).
    func cancel() {
        compileTask?.cancel()
        compileTask = nil
    }
}
