//
//  TypstCompiler.swift
//  Typist
//
//  Debounced compile pipeline: source → Rust FFI → PDFKit document.
//

import Observation
import Foundation
import os
import PDFKit

@MainActor
@Observable
final class TypstCompiler {
    enum CompileMode {
        case debounced
        case immediate
    }

    typealias CompileWorker = @Sendable (String, [String], String?) -> Result<Data, TypstBridgeError>
    typealias DocumentBuilder = @Sendable (Data) -> PDFDocument?
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct CompileRequest: Sendable {
        let source: String
        let fontPaths: [String]
        let rootDir: String?
        let generation: UInt64
    }

    private struct PDFDocumentBox: @unchecked Sendable {
        let document: PDFDocument
    }

    private enum WorkerResult: Sendable {
        case success(PDFDocumentBox)
        case failure(TypstBridgeError)
    }

    private static let compileDelay = Duration.milliseconds(350)
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Typist",
        category: "TypstCompiler"
    )
    nonisolated private static let signposter = OSSignposter(logger: logger)

    private(set) var pdfDocument: PDFDocument?
    private(set) var errorMessage: String?
    private(set) var isCompiling: Bool = false
    /// Tracks whether a compiled PDF is currently available.
    private(set) var compiledOnce: Bool = false

    private let compileWorker: CompileWorker
    private let documentBuilder: DocumentBuilder
    private let sleep: Sleep

    private var debounceTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    private var scheduledRequest: CompileRequest?
    private var pendingRequest: CompileRequest?
    private var compileGeneration: UInt64 = 0

    init(
        compileWorker: @escaping CompileWorker = TypstBridge.compile,
        documentBuilder: @escaping DocumentBuilder = { PDFDocument(data: $0) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.compileWorker = compileWorker
        self.documentBuilder = documentBuilder
        self.sleep = sleep
    }

    func compile(source: String, fontPaths: [String], rootDir: String? = nil, mode: CompileMode = .debounced) {
        compileGeneration &+= 1
        let request = CompileRequest(
            source: source,
            fontPaths: fontPaths,
            rootDir: rootDir,
            generation: compileGeneration
        )
        enqueue(request, mode: mode)
    }

    func compileNow(source: String, fontPaths: [String], rootDir: String? = nil) {
        compile(source: source, fontPaths: fontPaths, rootDir: rootDir, mode: .immediate)
    }

    /// Clear current preview content and cancel any in-flight compilation.
    func clearPreview() {
        debounceTask?.cancel()
        debounceTask = nil
        scheduledRequest = nil
        pendingRequest = nil
        compileGeneration &+= 1
        isCompiling = false
        pdfDocument = nil
        errorMessage = nil
        compiledOnce = false
    }

    /// Cancel any in-flight compilation (e.g. when document is closed).
    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        scheduledRequest = nil
        pendingRequest = nil
        compileGeneration &+= 1
        isCompiling = false
    }

    private func enqueue(_ request: CompileRequest, mode: CompileMode) {
        switch mode {
        case .debounced:
            scheduledRequest = request
            debounceTask?.cancel()
            let sleep = self.sleep
            debounceTask = Task { [weak self] in
                do {
                    try await sleep(Self.compileDelay)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                self?.activateScheduledRequest(generation: request.generation)
            }
        case .immediate:
            debounceTask?.cancel()
            debounceTask = nil
            scheduledRequest = nil
            pendingRequest = request
            startNextCompileIfNeeded()
        }
    }

    private func activateScheduledRequest(generation: UInt64) {
        guard scheduledRequest?.generation == generation else { return }
        pendingRequest = scheduledRequest
        scheduledRequest = nil
        debounceTask = nil
        startNextCompileIfNeeded()
    }

    private func startNextCompileIfNeeded() {
        guard activeTask == nil, let request = pendingRequest else { return }

        pendingRequest = nil
        isCompiling = true

        let compileWorker = self.compileWorker
        let documentBuilder = self.documentBuilder
        activeTask = Task { [weak self] in
            let workerResult = await Task.detached(priority: .userInitiated) {
                Self.runCompilation(
                    request: request,
                    compileWorker: compileWorker,
                    documentBuilder: documentBuilder
                )
            }.value
            self?.finishCompilation(workerResult, generation: request.generation)
        }
    }

    private func finishCompilation(_ result: WorkerResult, generation: UInt64) {
        activeTask = nil

        if generation == compileGeneration {
            let applyInterval = Self.signposter.beginInterval("typst.preview_apply")
            switch result {
            case .success(let box):
                pdfDocument = box.document
                errorMessage = nil
                compiledOnce = true
            case .failure(let error):
                // Keep the last successful PDF visible; only update the error banner.
                errorMessage = error.localizedDescription
            }
            Self.signposter.endInterval("typst.preview_apply", applyInterval)
        }

        if pendingRequest != nil {
            startNextCompileIfNeeded()
        } else {
            isCompiling = false
        }
    }

    nonisolated private static func runCompilation(
        request: CompileRequest,
        compileWorker: CompileWorker,
        documentBuilder: DocumentBuilder
    ) -> WorkerResult {
        let compileInterval = signposter.beginInterval("typst.compile")
        let result = compileWorker(request.source, request.fontPaths, request.rootDir)
        signposter.endInterval("typst.compile", compileInterval)

        switch result {
        case .success(let pdfData):
            let decodeInterval = signposter.beginInterval("typst.pdf_decode")
            defer { signposter.endInterval("typst.pdf_decode", decodeInterval) }

            guard let document = documentBuilder(pdfData) else {
                return .failure(.compilationFailed("Failed to decode compiled PDF."))
            }
            return .success(PDFDocumentBox(document: document))
        case .failure(let error):
            return .failure(error)
        }
    }
}
