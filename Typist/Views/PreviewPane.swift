//
//  PreviewPane.swift
//  Typist
//
//  Shows the compiled PDF, a compilation error banner, or a placeholder
//  when the Typst compiler library hasn't been linked yet.
//

import SwiftUI
import PDFKit

private struct CompilationErrorPresentation {
    let summary: String
    let detail: String
    let location: String?
}

private extension View {
    @ViewBuilder
    func compilationErrorSurface(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(
                    .regular.tint(Color.catppuccinDanger.opacity(0.14)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.catppuccinDanger.opacity(0.22), lineWidth: 1)
                }
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.catppuccinDanger.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.catppuccinDanger.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

// MARK: - PDFKit wrapper

/// PDFView subclass that refuses first-responder so it never steals focus
/// from the text editor (which would dismiss the software keyboard on iPadOS).
private final class PassivePDFView: PDFView {
    override var canBecomeFirstResponder: Bool { false }
}

final class PDFContainerView: UIView {
    fileprivate let pdfView = PassivePDFView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(pdfView)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let focusCoordinator: EditorFocusCoordinator?

    func makeUIView(context: Context) -> PDFContainerView {
        let container = PDFContainerView()
        let pdfView = container.pdfView
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .catppuccinMantle
        return container
    }

    func updateUIView(_ container: PDFContainerView, context: Context) {
        let pdfView = container.pdfView
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
        focusCoordinator?.setResignSuppressed(true)
        pdfView.document = document
        pdfView.backgroundColor = .catppuccinMantle

        if let pageIndex = savedPageIndex,
           let scale = savedScale,
           let newPage = document.page(at: pageIndex) {
            pdfView.autoScales = false
            pdfView.scaleFactor = scale
            DispatchQueue.main.async {
                pdfView.go(to: PDFDestination(page: newPage, at: CGPoint(x: 0, y: savedPageY)))
                focusCoordinator?.setResignSuppressed(false)
            }
        } else {
            // First load: let PDFView pick the initial scale automatically.
            pdfView.autoScales = true
            DispatchQueue.main.async {
                focusCoordinator?.setResignSuppressed(false)
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
    var focusCoordinator: EditorFocusCoordinator? = nil
    @State private var isShowingErrorDetails = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pdf = compiler.pdfDocument {
                PDFKitView(document: pdf, focusCoordinator: focusCoordinator)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                placeholderView
            }

            if let error = compiler.errorMessage {
                errorToast(error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if compiler.isCompiling {
                ProgressView()
                    .padding(8)
                    .catppuccinFloatingSurface(cornerRadius: 8)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .onChange(of: source, initial: true) { compileIfNeeded() }
        .onChange(of: fontPaths) { compileIfNeeded() }
        .onChange(of: rootDir) { compileIfNeeded() }
        .onChange(of: compileToken) { compileIfNeeded() }
        .onChange(of: compiler.errorMessage, initial: true) { _, newValue in
            let shouldExpand = (newValue != nil) && (compiler.pdfDocument == nil)
            guard shouldExpand != isShowingErrorDetails else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingErrorDetails = shouldExpand
            }
        }
        .onDisappear {
            focusCoordinator?.setResignSuppressed(false)
            compiler.cancel()
        }
        .animation(.easeInOut(duration: 0.2), value: compiler.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: isShowingErrorDetails)
    }

    /// Only compile when the source contains meaningful content.
    private func compileIfNeeded() {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            compiler.clearPreview()
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

    private func errorToast(_ message: String) -> some View {
        let presentation = errorPresentation(from: message)
        let showsDetailToggle =
            presentation.detail != presentation.summary || presentation.detail.count > 140

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.catppuccinDanger)
                    .frame(width: 30, height: 30)
                    .background(Color.catppuccinDanger.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Compilation Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.catppuccinText)
                    Text(presentation.summary)
                        .font(.footnote)
                        .foregroundStyle(Color.catppuccinText.opacity(0.86))
                        .lineLimit(isShowingErrorDetails ? nil : 2)

                    if let location = presentation.location {
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
                                .font(.system(size: 11, weight: .semibold))
                            Text(location)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(Color.catppuccinText.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.catppuccinDanger.opacity(0.08), in: Capsule())
                    }
                }

                Spacer(minLength: 8)

                if showsDetailToggle {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingErrorDetails.toggle()
                        }
                    } label: {
                        Text(isShowingErrorDetails ? "Hide Details" : "Show Details")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.catppuccinDanger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.catppuccinDanger.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if isShowingErrorDetails {
                ScrollView {
                    Text(presentation.detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.catppuccinText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .compilationErrorSurface(cornerRadius: 18)
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
    }

    private func normalizedErrorMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func errorPresentation(from message: String) -> CompilationErrorPresentation {
        let normalizedMessage = normalizedErrorMessage(message)
        let lines = normalizedMessage.components(separatedBy: .newlines)

        let location = lines.compactMap(parsedLocation(from:)).first
        let summary = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && parsedLocation(from: $0) == nil }) ?? normalizedMessage

        return CompilationErrorPresentation(
            summary: summary,
            detail: normalizedMessage,
            location: location
        )
    }

    private func parsedLocation(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return nil }
        let candidate = String(trimmed.dropFirst().dropLast())
        let parts = candidate.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let line = Int(parts[parts.count - 2]),
              let column = Int(parts[parts.count - 1]),
              line > 0,
              column > 0 else {
            return nil
        }

        let path = parts.dropLast(2).joined(separator: ":")
        return path.isEmpty ? nil : candidate
    }
}
