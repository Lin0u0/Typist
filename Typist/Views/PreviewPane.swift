//
//  PreviewPane.swift
//  Typist
//
//  Shows the compiled PDF, a compilation error banner, or a placeholder
//  when the Typst compiler library hasn't been linked yet.
//

import SwiftUI
import PDFKit
import NaturalLanguage

private struct CompilationErrorPresentation {
    let summary: String
    let detail: String
    let location: String?
}

private struct PreviewStatistics {
    let pageCount: Int
    let wordCount: Int
    let characterCount: Int
}

private struct PreviewStatisticItem: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

private extension Unicode.Scalar {
    var isCJKUnifiedIdeograph: Bool {
        switch value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x30000...0x3134F:
            true
        default:
            false
        }
    }
}

private extension Character {
    var countsTowardPreviewCharacter: Bool {
        !unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
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
    var scrollTarget: PreviewScrollTarget?
    var onTapLocation: ((_ page: Int, _ yPoints: Float) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapLocation: onTapLocation)
    }

    func makeUIView(context: Context) -> PDFContainerView {
        let container = PDFContainerView()
        let pdfView = container.pdfView
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.isAccessibilityElement = false
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = "editor.preview"
        container.accessibilityLabel = L10n.a11yPreviewLabel
        container.accessibilityHint = L10n.a11yPreviewHint
        container.accessibilityValue = L10n.a11yPreviewValueReady

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 2
        pdfView.addGestureRecognizer(tapGesture)
        context.coordinator.pdfView = pdfView

        return container
    }

    func updateUIView(_ container: PDFContainerView, context: Context) {
        context.coordinator.onTapLocation = onTapLocation
        context.coordinator.pdfView = container.pdfView
        container.accessibilityLabel = L10n.a11yPreviewLabel
        container.accessibilityHint = L10n.a11yPreviewHint
        container.accessibilityValue = L10n.a11yPreviewValueReady
        container.reloadDocument(document, focusCoordinator: focusCoordinator)

        if let target = scrollTarget {
            container.scrollToPosition(page: target.page, yPoints: target.yPoints)
        }
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var onTapLocation: ((_ page: Int, _ yPoints: Float) -> Void)?

        init(onTapLocation: ((_ page: Int, _ yPoints: Float) -> Void)?) {
            self.onTapLocation = onTapLocation
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView, let document = pdfView.document else { return }
            let tapPoint = gesture.location(in: pdfView)

            guard let tappedPage = pdfView.page(for: tapPoint, nearest: true) else { return }
            let pagePoint = pdfView.convert(tapPoint, to: tappedPage)
            let pageIndex = document.index(for: tappedPage)

            // PDFKit Y is from bottom-left; convert to top-down.
            let pageBounds = tappedPage.bounds(for: .mediaBox)
            let yFromTop = pageBounds.height - pagePoint.y

            onTapLocation?(pageIndex, Float(yFromTop))
        }
    }
}

extension PDFContainerView {
    func scrollToPosition(page: Int, yPoints: Float) {
        guard let document = pdfView.document,
              page < document.pageCount,
              let pdfPage = document.page(at: page) else { return }

        // Convert top-down Y to PDFKit bottom-up coordinate.
        let pageBounds = pdfPage.bounds(for: .mediaBox)
        let pdfY = pageBounds.height - CGFloat(yPoints)
        let destination = PDFDestination(page: pdfPage, at: CGPoint(x: 0, y: pdfY))
        pdfView.go(to: destination)
    }
}

// MARK: - PreviewPane

struct PreviewPane: View {
    var compiler: TypstCompiler
    var source: String
    var fontPaths: [String] = []
    var rootDir: String?
    var previewCacheDescriptor: CompiledPreviewCacheDescriptor? = nil
    var compileToken: UUID = UUID()
    var focusCoordinator: EditorFocusCoordinator? = nil
    /// The actual entry file name — Typst FFI internally reports it as "main.typ".
    var entryFileName: String = "main.typ"
    var onGoToError: ((_ file: String, _ line: Int, _ column: Int) -> Void)? = nil
    @ScaledMetric(relativeTo: .caption2) private var previewStatsCardWidth = 126
    @ScaledMetric(relativeTo: .caption2) private var previewStatsMinHeight = 34
    @ScaledMetric(relativeTo: .caption2) private var previewStatsHorizontalPadding = 8
    @ScaledMetric(relativeTo: .caption2) private var previewStatsVerticalPadding = 7
    @State private var isShowingErrorDetails = false
    @State private var isShowingStatsDetails = false

    private var previewStatistics: PreviewStatistics? {
        guard let pdf = compiler.pdfDocument else { return nil }
        return PreviewStatistics(
            pageCount: max(pdf.pageCount, 0),
            wordCount: source.previewWordCount,
            characterCount: source.previewCharacterCount
        )
    }

    private var prefersChineseStatistics: Bool {
        source.containsCJKIdeographs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pdf = compiler.pdfDocument {
                PDFKitView(document: pdf, focusCoordinator: focusCoordinator)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel(L10n.a11yPreviewLabel)
                    .accessibilityHint(L10n.a11yPreviewHint)
                    .accessibilityValue(
                        compiler.errorMessage == nil ? L10n.a11yPreviewValueReady : L10n.a11yPreviewValueError
                    )
                    .accessibilityIdentifier("editor.preview")
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

            if let stats = previewStatistics {
                previewStatisticsButton(stats)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: source, initial: true) { compileIfNeeded() }
        .onChange(of: fontPaths) { compileIfNeeded() }
        .onChange(of: rootDir) { compileIfNeeded() }
        .onChange(of: compileToken) { compileIfNeeded() }
        .onChange(of: compiler.pdfDocument != nil) { _, hasPreview in
            guard !hasPreview else { return }
            isShowingStatsDetails = false
        }
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
        compiler.compile(
            source: source,
            fontPaths: fontPaths,
            rootDir: rootDir,
            previewCachePolicy: .useCacheIfValid,
            previewCacheDescriptor: previewCacheDescriptor
        )
    }

    // MARK: Sub-views

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: compiler.errorMessage == nil ? "doc.richtext" : "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.a11yPreviewPlaceholderLabel)
        .accessibilityHint(L10n.a11yPreviewPlaceholderHint)
        .accessibilityValue(compiler.errorMessage == nil ? L10n.a11yPreviewValueEmpty : L10n.a11yPreviewValueError)
        .accessibilityIdentifier("editor.preview.placeholder")
    }

    private func previewStatisticsButton(_ stats: PreviewStatistics) -> some View {
        let pageText = L10n.previewStatsPages(stats.pageCount)
        let cardCornerRadius: CGFloat = 18
        let expandedItems: [PreviewStatisticItem]

        if prefersChineseStatistics {
            expandedItems = [
                PreviewStatisticItem(title: L10n.tr("preview.stats.characters.label"), value: "\(stats.characterCount)"),
                PreviewStatisticItem(title: L10n.tr("preview.stats.tokens.label"), value: "\(stats.wordCount)")
            ]
        } else {
            expandedItems = [
                PreviewStatisticItem(title: L10n.tr("preview.stats.words.label"), value: "\(stats.wordCount)"),
                PreviewStatisticItem(title: L10n.tr("preview.stats.characters.label"), value: "\(stats.characterCount)")
            ]
        }

        let accessibilitySecondaryText = prefersChineseStatistics
            ? L10n.previewStatsTokens(stats.wordCount)
            : L10n.previewStatsWords(stats.wordCount)
        let accessibilityCharacterText = L10n.previewStatsCharacters(stats.characterCount)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isShowingStatsDetails.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: isShowingStatsDetails ? 6 : 0) {
                HStack(spacing: 6) {
                    Label(pageText, systemImage: "doc.text")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    Image(systemName: isShowingStatsDetails ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if isShowingStatsDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(expandedItems) { item in
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.95)

                                Spacer(minLength: 6)

                                Text(item.value)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 6).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
            .frame(minHeight: previewStatsMinHeight, alignment: .leading)
            .frame(width: previewStatsCardWidth, alignment: .leading)
            .padding(.horizontal, previewStatsHorizontalPadding)
            .padding(.vertical, previewStatsVerticalPadding)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .systemFloatingSurface(cornerRadius: cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.a11yPreviewLabel)
        .accessibilityValue(
            isShowingStatsDetails
                ? L10n.previewStatsExpandedValue(
                    pages: pageText,
                    words: accessibilitySecondaryText,
                    characters: accessibilityCharacterText
                )
                : pageText
        )
        .accessibilityHint(isShowingStatsDetails ? L10n.previewStatsHintExpanded : L10n.previewStatsHintCollapsed)
        .accessibilityIdentifier("editor.preview.stats")
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
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Compilation Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(presentation.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(isShowingErrorDetails ? nil : 2)

                    if let location = presentation.location {
                        Button {
                            if let parsed = firstErrorLocation(from: message) {
                                onGoToError?(parsed.file, parsed.line, parsed.column)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "scope")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(location)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if onGoToError != nil {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(onGoToError == nil)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.tr("Compilation Error")). \(presentation.summary)")
        .accessibilityValue(presentation.location ?? "")
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

    private struct ParsedErrorLocation {
        let file: String
        let line: Int
        let column: Int
        var displayText: String { "\(file):\(line):\(column)" }
    }

    private func parsedLocation(from line: String) -> String? {
        parseErrorLocation(from: line)?.displayText
    }

    private func parseErrorLocation(from line: String) -> ParsedErrorLocation? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return nil }
        let candidate = String(trimmed.dropFirst().dropLast())
        let parts = candidate.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let lineNum = Int(parts[parts.count - 2]),
              let column = Int(parts[parts.count - 1]),
              lineNum > 0,
              column > 0 else {
            return nil
        }

        var path = parts.dropLast(2).joined(separator: ":")
        guard !path.isEmpty else { return nil }
        // Typst FFI names the entry source "main.typ" internally — map to actual name.
        if path == "main.typ" && entryFileName != "main.typ" {
            path = entryFileName
        }
        return ParsedErrorLocation(file: path, line: lineNum, column: column)
    }

    private func firstErrorLocation(from message: String) -> ParsedErrorLocation? {
        let lines = normalizedErrorMessage(message).components(separatedBy: .newlines)
        return lines.lazy.compactMap(parseErrorLocation(from:)).first
    }
}

private extension String {
    var containsCJKIdeographs: Bool {
        unicodeScalars.contains { $0.isCJKUnifiedIdeograph }
    }

    var previewWordCount: Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = self

        var count = 0
        tokenizer.enumerateTokens(in: startIndex..<endIndex) { range, _ in
            if self[range].contains(where: { !$0.isWhitespace }) {
                count += 1
            }
            return true
        }
        return count
    }

    var previewCharacterCount: Int {
        reduce(into: 0) { count, character in
            if character.countsTowardPreviewCharacter {
                count += 1
            }
        }
    }
}
