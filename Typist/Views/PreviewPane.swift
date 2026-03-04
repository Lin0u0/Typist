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

/// PDFView subclass that refuses first-responder so it never steals focus
/// from the text editor (which would dismiss the software keyboard on iPadOS).
private final class PassivePDFView: PDFView {
    override var canBecomeFirstResponder: Bool { false }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PassivePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .catppuccinMantle
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Save scroll position based on view geometry rather than currentDestination.
        // currentDestination tracks the last *navigation* target, not the current
        // scroll offset, so it drifts by one page on every recompile.
        var savedPageIndex: Int?
        var savedPageY: CGFloat = .greatestFiniteMagnitude  // PDF y-coord at visible top
        var savedScale: CGFloat?

        if let oldDoc = pdfView.document,
           let page = pdfView.currentPage {
            let box = page.bounds(for: .mediaBox)
            let pageInView = pdfView.convert(box, from: page)
            // How much of the page (in view-space) is scrolled above the visible top?
            if pageInView.height > 0 {
                let hiddenFraction = max(0, -pageInView.minY) / pageInView.height
                // Convert back to PDF coordinates (y=0 at bottom, y=height at top).
                savedPageY = box.maxY - hiddenFraction * box.height
            }
            savedPageIndex = oldDoc.index(for: page)
            savedScale = pdfView.scaleFactor
        }

        // Prevent PDFKit from dismissing the software keyboard while it
        // tears down / rebuilds page views for the new document.
        TypstTextView.suppressResignFirstResponder = true
        pdfView.document = document
        pdfView.backgroundColor = .catppuccinMantle

        if let pageIndex = savedPageIndex,
           let scale = savedScale,
           let newPage = document.page(at: pageIndex) {
            pdfView.autoScales = false
            pdfView.scaleFactor = scale
            DispatchQueue.main.async {
                pdfView.go(to: PDFDestination(page: newPage, at: CGPoint(x: 0, y: savedPageY)))
                TypstTextView.suppressResignFirstResponder = false
            }
        } else {
            // First load: let PDFView pick the initial scale automatically.
            pdfView.autoScales = true
            DispatchQueue.main.async {
                TypstTextView.suppressResignFirstResponder = false
            }
        }
    }
}

// MARK: - PreviewPane

struct PreviewPane: View {
    var compiler: TypstCompiler
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
        .background(Color.catppuccinMantle)
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
