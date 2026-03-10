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
        self
            .systemFloatingSurface(cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            }
    }
}

// MARK: - PDFKit wrapper

/// PDFView subclass that refuses first-responder so it never steals focus
/// from the text editor (which would dismiss the software keyboard on iPadOS).
private final class PassivePDFView: PDFView {
    override var canBecomeFirstResponder: Bool { false }
}

private struct PDFPreviewScrollState {
    let contentOffset: CGPoint
    let scaleFactor: CGFloat
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

    func reloadDocument(_ document: PDFDocument, focusCoordinator: EditorFocusCoordinator?) {
        pdfView.backgroundColor = .secondarySystemBackground

        guard pdfView.document !== document else {
            focusCoordinator?.setResignSuppressed(false)
            return
        }

        let savedState = captureScrollState()

        // Prevent PDFKit from dismissing the software keyboard while it
        // tears down / rebuilds page views for the new document.
        focusCoordinator?.setResignSuppressed(true)
        pdfView.document = document

        guard let savedState else {
            // First load: let PDFView pick the initial scale automatically.
            pdfView.autoScales = true
            DispatchQueue.main.async { [weak self, weak focusCoordinator] in
                guard let self, self.pdfView.document === document else { return }
                focusCoordinator?.setResignSuppressed(false)
            }
            return
        }

        pdfView.autoScales = false
        pdfView.scaleFactor = savedState.scaleFactor

        DispatchQueue.main.async { [weak self, weak focusCoordinator] in
            guard let self, self.pdfView.document === document else { return }

            self.layoutIfNeeded()
            self.pdfView.layoutIfNeeded()
            self.pdfView.scaleFactor = self.clampedScaleFactor(savedState.scaleFactor)

            if let scrollView = self.findScrollView(in: self.pdfView) {
                scrollView.layoutIfNeeded()
                let clampedOffset = self.clampedContentOffset(
                    savedState.contentOffset,
                    in: scrollView
                )
                if scrollView.contentOffset != clampedOffset {
                    scrollView.setContentOffset(clampedOffset, animated: false)
                }
            }

            focusCoordinator?.setResignSuppressed(false)
        }
    }

    private func captureScrollState() -> PDFPreviewScrollState? {
        guard pdfView.document != nil,
              let scrollView = findScrollView(in: pdfView) else {
            return nil
        }

        return PDFPreviewScrollState(
            contentOffset: scrollView.contentOffset,
            scaleFactor: pdfView.scaleFactor
        )
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    private func clampedContentOffset(_ contentOffset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let inset = scrollView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)

        return CGPoint(
            x: min(max(contentOffset.x, minX), maxX),
            y: min(max(contentOffset.y, minY), maxY)
        )
    }

    private func clampedScaleFactor(_ scaleFactor: CGFloat) -> CGFloat {
        let minScale = pdfView.minScaleFactor > 0 ? pdfView.minScaleFactor : scaleFactor
        let maxScale = pdfView.maxScaleFactor > 0 ? pdfView.maxScaleFactor : scaleFactor
        return min(max(scaleFactor, minScale), maxScale)
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
        pdfView.backgroundColor = .secondarySystemBackground
        return container
    }

    func updateUIView(_ container: PDFContainerView, context: Context) {
        container.reloadDocument(document, focusCoordinator: focusCoordinator)
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
                    .systemFloatingSurface(cornerRadius: 8)
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
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func errorToast(_ message: String) -> some View {
        let presentation = errorPresentation(from: message)
        let showsDetailToggle =
            presentation.detail != presentation.summary || presentation.detail.count > 140

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Compilation Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(presentation.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
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
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if isShowingErrorDetails {
                ScrollView {
                    Text(presentation.detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
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
