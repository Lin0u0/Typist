//
//  PreviewPane.swift
//  Typist
//
//  Shows the compiled PDF, a compilation error banner, or a placeholder
//  when the Typst compiler library hasn't been linked yet.
//

import SwiftUI
import PDFKit

// MARK: - PDFKit wrapper

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .catppuccinMantle
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Preserve scroll position when the document updates.
        let dest = pdfView.currentDestination
        pdfView.document = document
        // PDFView may reset its background when a new document is set.
        pdfView.backgroundColor = .catppuccinMantle
        if let dest {
            pdfView.go(to: dest)
        }
    }
}

// MARK: - PreviewPane

struct PreviewPane: View {
    @State private var compiler = TypstCompiler()
    var source: String
    var fontPaths: [String] = []
    var rootDir: String?
    var compileToken: UUID = UUID()

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pdf = compiler.pdfDocument {
                PDFKitView(document: pdf)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                placeholderView
            }

            if let error = compiler.errorMessage {
                errorBanner(error)
            }

            if compiler.isCompiling {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .onChange(of: source, initial: true) { compileIfNeeded() }
        .onChange(of: fontPaths) { compileIfNeeded() }
        .onChange(of: rootDir) { compileIfNeeded() }
        .onChange(of: compileToken) { compileIfNeeded() }
        .onDisappear {
            compiler.cancel()
        }
    }

    /// Only compile when the source contains meaningful content.
    private func compileIfNeeded() {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        compiler.compile(source: source, fontPaths: fontPaths, rootDir: rootDir)
    }

    // MARK: Sub-views

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: compiler.errorMessage == nil ? "doc.richtext" : "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(compiler.errorMessage == nil ? "Preview" : "Compilation Error")
                .font(.title2)
                .foregroundStyle(.secondary)
            if compiler.errorMessage == nil {
                Text("Start typing to see a live preview")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.catppuccinBase)
    }

    private func errorBanner(_ message: String) -> some View {
        ScrollView {
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .background(Color.red.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }
}
