//
//  TypstTextView.swift
//  Typist
//

import os
import UIKit
import UniformTypeIdentifiers

final class TypstTextView: UITextView {
    enum PasteFragment {
        case text(String)
        case imageData(Data, suggestedFileName: String?)
        case imageRemoteURL(URL, suggestedFileName: String?)
    }

    private let highlighter = SyntaxHighlighter()
    private lazy var highlightScheduler = HighlightScheduler { [weak self] in
        self?.applyHighlightingNow()
    }
    private(set) var gutterView: LineNumberGutterView!
    private var storedTheme: EditorTheme = .system
    private var appearanceRegistration: (any UITraitChangeRegistration)?
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Typist", category: "EditorHighlight")
    private static let signposter = OSSignposter(logger: logger)

    /// When true, `resignFirstResponder()` is refused for this editor instance.
    /// Set by PDFKitView during document reload to prevent PDFKit from
    /// dismissing the software keyboard on iPadOS.
    var suppressResignFirstResponder = false

    var onPhotoButtonTapped: (() -> Void)? {
        didSet { (inputAccessoryView as? KeyboardAccessoryView)?.onPhotoButtonTapped = onPhotoButtonTapped }
    }
    var onImagePasted: ((Data) -> Void)?
    var onRichPaste: (([PasteFragment]) -> Void)?
    private let pasteImageTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .webP]

    // MARK: - Init (Force TextKit 1)

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)

        configureAppearance()
        setupGutter()
        setupAccessoryView()
        setupFindInteraction()
        setupAppearanceObservation()
        setupKeyboardAvoidance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
        setupGutter()
        setupAccessoryView()
        setupFindInteraction()
        setupAppearanceObservation()
        setupKeyboardAvoidance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configureAppearance() {
        font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        autocorrectionType = .no
        autocapitalizationType = .none
        smartDashesType = .no
        smartQuotesType = .no
        spellCheckingType = .no
        backgroundColor = .clear
        textColor = .label
    }

    private func setupGutter() {
        gutterView = LineNumberGutterView(textView: self)
        addSubview(gutterView)
        updateGutterLayout()
    }

    private func updateGutterLayout() {
        let width = gutterView.gutterWidth
        textContainerInset = UIEdgeInsets(top: 12, left: width + 4, bottom: 12, right: 12)
        gutterView.frame = CGRect(x: 0, y: 0, width: width, height: max(contentSize.height, bounds.height))
        gutterView.setNeedsDisplay()
    }

    private func setupAccessoryView() {
        inputAccessoryView = KeyboardAccessoryView(textView: self)
    }

    private func setupFindInteraction() {
        isFindInteractionEnabled = true
    }

    private func setupAppearanceObservation() {
        appearanceRegistration = registerForTraitChanges(
            [UITraitUserInterfaceStyle.self]
        ) { (view: TypstTextView, _: UITraitCollection) in
            view.typingAttributes[.foregroundColor] = view.storedTheme.text
            view.scheduleHighlighting(.immediate)
        }
    }

    // MARK: - Cmd+F Key Command

    override var keyCommands: [UIKeyCommand]? {
        let findCommand = UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(showFind))
        findCommand.discoverabilityTitle = L10n.tr("action.find_replace")
        return (super.keyCommands ?? []) + [findCommand]
    }

    @objc private func showFind() {
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    // MARK: - First Responder Guard

    @discardableResult
    override func resignFirstResponder() -> Bool {
        if suppressResignFirstResponder { return false }
        return super.resignFirstResponder()
    }

    // MARK: - Auto-pair Integration

    override func insertText(_ text: String) {
        if AutoPairEngine.handleInsert(text, in: self) {
            // applyHighlighting() is handled by Coordinator.textViewDidChange below
            delegate?.textViewDidChange?(self)
            return
        }
        super.insertText(text)
    }

    override func deleteBackward() {
        if AutoPairEngine.handleDelete(in: self) {
            // applyHighlighting() is handled by Coordinator.textViewDidChange below
            delegate?.textViewDidChange?(self)
            return
        }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        let fragments = pasteFragmentsFromPasteboard()
        guard !fragments.isEmpty else {
            super.paste(sender)
            return
        }

        if let onRichPaste {
            onRichPaste(fragments)
            return
        }

        var textBuffer = ""
        for fragment in fragments {
            switch fragment {
            case .text(let text):
                textBuffer.append(text)
            case .imageData(let data, _):
                if !textBuffer.isEmpty {
                    if let range = selectedTextRange {
                        replace(range, withText: textBuffer)
                    } else {
                        insertText(textBuffer)
                    }
                    textBuffer = ""
                }
                onImagePasted?(data)
            case .imageRemoteURL:
                // Fallback path cannot import remote URLs synchronously.
                // If rich paste handler isn't set, ignore remote image fragments.
                continue
            }
        }
        if !textBuffer.isEmpty {
            if let range = selectedTextRange {
                replace(range, withText: textBuffer)
            } else {
                insertText(textBuffer)
            }
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            if !pasteFragmentsFromPasteboard().isEmpty {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = gutterView.gutterWidth
        gutterView.frame = CGRect(x: 0, y: 0, width: width, height: max(contentSize.height, bounds.height))
        gutterView.setNeedsDisplay()
    }

    // MARK: - Theme

    func applyTheme(_ theme: EditorTheme) {
        guard theme.id != storedTheme.id else { return }
        storedTheme = theme
        backgroundColor = theme.background
        textColor = theme.text
        typingAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: theme.text,
        ]
        highlighter.updateTheme(theme)
        gutterView.applyTheme(theme)
        scheduleHighlighting(.immediate)
    }

    // MARK: - Highlighting

    func scheduleHighlighting(_ mode: HighlightMode, textChanged: Bool = false) {
        if textChanged {
            gutterView.textDidChange()
            setNeedsLayout()
        }
        highlightScheduler.schedule(mode)
    }

    private func applyHighlightingNow() {
        let interval = Self.signposter.beginInterval("editor.highlight")
        highlighter.highlight(textStorage)
        gutterView.setNeedsDisplay()
        Self.signposter.endInterval("editor.highlight", interval)
    }

    // MARK: - Keyboard Avoidance

    private func setupKeyboardAvoidance() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard window != nil,
              let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        // How much does the keyboard overlap the bottom of this view (in window coordinates)?
        let viewBottomY = convert(CGPoint(x: 0, y: bounds.maxY), to: nil).y
        let overlap = max(0, viewBottomY - endFrame.minY)

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7

        UIView.animate(
            withDuration: duration, delay: 0,
            options: [.beginFromCurrentState, UIView.AnimationOptions(rawValue: curveRaw << 16)]
        ) {
            self.contentInset.bottom = overlap
            self.verticalScrollIndicatorInsets.bottom = overlap
        } completion: { _ in
            if overlap > 0 { self.scrollCursorToVisible() }
        }
    }

    private func scrollCursorToVisible() {
        guard let range = selectedTextRange else { return }
        let rect = caretRect(for: range.end).insetBy(dx: 0, dy: -8)
        scrollRectToVisible(rect, animated: true)
    }

    private func pasteFragmentsFromPasteboard() -> [PasteFragment] {
        let pasteboard = UIPasteboard.general
        var fragments: [PasteFragment] = []

        for item in pasteboard.items {
            if let htmlFragments = htmlFragmentsFromPasteboardItem(item),
               !htmlFragments.isEmpty {
                fragments.append(contentsOf: htmlFragments)
                continue
            }
            if let (data, suggestedName) = imageDataFromPasteboardItem(item) {
                fragments.append(.imageData(data, suggestedFileName: suggestedName))
                continue
            }
            if let (remoteURL, suggestedName) = remoteImageURLFromPasteboardItem(item) {
                fragments.append(.imageRemoteURL(remoteURL, suggestedFileName: suggestedName))
                continue
            }
            if let text = textFromPasteboardItem(item),
               !text.isEmpty,
               !shouldSuppressTextFallback(text, for: item) {
                fragments.append(.text(text))
            }
        }

        if fragments.isEmpty, let string = pasteboard.string, !string.isEmpty {
            fragments.append(.text(string))
        }

        if fragments.isEmpty, let image = pasteboard.image {
            if let data = image.pngData() ?? image.jpegData(compressionQuality: 1.0) {
                fragments.append(.imageData(data, suggestedFileName: nil))
            }
        }

        return mergedAdjacentTextFragments(fragments)
    }

    private func htmlFragmentsFromPasteboardItem(_ item: [String: Any]) -> [PasteFragment]? {
        guard let raw = item[UTType.html.identifier] ?? item["public.html"] else { return nil }
        let html: String?
        if let str = raw as? String {
            html = str
        } else if let data = raw as? Data {
            html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        } else {
            html = nil
        }
        guard let html, !html.isEmpty else { return nil }

        let imgPattern = #"(?is)<img\b[^>]*>"#
        guard let imgRegex = try? NSRegularExpression(pattern: imgPattern) else { return nil }

        let nsHTML = html as NSString
        let matches = imgRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else { return nil }

        var fragments: [PasteFragment] = []
        var cursor = 0
        for match in matches {
            let textRange = NSRange(location: cursor, length: max(0, match.range.location - cursor))
            if textRange.length > 0 {
                let textChunk = nsHTML.substring(with: textRange)
                let normalized = normalizedHTMLText(textChunk)
                if !normalized.isEmpty {
                    fragments.append(.text(normalized))
                }
            }

            let tag = nsHTML.substring(with: match.range)
            if let (remoteURL, suggestedName) = remoteImageFromHTMLTag(tag) {
                fragments.append(.imageRemoteURL(remoteURL, suggestedFileName: suggestedName))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let tail = nsHTML.substring(from: cursor)
            let normalizedTail = normalizedHTMLText(tail)
            if !normalizedTail.isEmpty {
                fragments.append(.text(normalizedTail))
            }
        }
        return fragments
    }

    private func remoteImageFromHTMLTag(_ tag: String) -> (URL, String?)? {
        let srcPattern = #"(?is)src\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))"#
        guard let srcRegex = try? NSRegularExpression(pattern: srcPattern) else { return nil }
        let nsTag = tag as NSString
        guard let match = srcRegex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)) else { return nil }

        var src: String?
        for index in 1...3 {
            let range = match.range(at: index)
            if range.location != NSNotFound, range.length > 0 {
                src = nsTag.substring(with: range)
                break
            }
        }
        guard var src else { return nil }
        src = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.hasPrefix("//") {
            src = "https:" + src
        }
        guard let url = URL(string: src),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return (url, suggestedFileName(fromRemoteURL: url))
    }

    private func normalizedHTMLText(_ html: String) -> String {
        var value = html
        let breakPatterns = [
            #"(?i)<br\s*/?>"#,
            #"(?i)</p>"#, #"(?i)</div>"#, #"(?i)</li>"#, #"(?i)</h[1-6]>"#, #"(?i)</blockquote>"#
        ]
        for pattern in breakPatterns {
            value = value.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)

        if let data = value.data(using: .utf8),
           let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
           ) {
            value = attributed.string
        }
        value = value.replacingOccurrences(of: "\u{00A0}", with: " ")
        value = value.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedAdjacentTextFragments(_ fragments: [PasteFragment]) -> [PasteFragment] {
        var merged: [PasteFragment] = []
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            merged.append(.text(textBuffer))
            textBuffer = ""
        }

        for fragment in fragments {
            switch fragment {
            case .text(let text):
                textBuffer.append(text)
            case .imageData, .imageRemoteURL:
                flushText()
                merged.append(fragment)
            }
        }
        flushText()
        return merged
    }

    private func textFromPasteboardItem(_ item: [String: Any]) -> String? {
        let textTypeIdentifiers = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier,
            "public.text",
        ]

        for identifier in textTypeIdentifiers {
            guard let raw = item[identifier] else { continue }
            if let text = raw as? String { return text }
            if let data = raw as? Data, let text = String(data: data, encoding: .utf8) { return text }
        }
        return nil
    }

    private func imageDataFromPasteboardItem(_ item: [String: Any]) -> (Data, String?)? {
        var suggestedName: String?
        var fileURLFromItem: URL?
        if let fileURLRaw = item[UTType.fileURL.identifier] {
            if let fileURL = fileURLRaw as? URL {
                fileURLFromItem = fileURL
                suggestedName = fileURL.lastPathComponent
            } else if let fileURLString = fileURLRaw as? String,
                      let fileURL = URL(string: fileURLString) {
                fileURLFromItem = fileURL
                suggestedName = fileURL.lastPathComponent
            } else if let fileURLData = fileURLRaw as? Data,
                      let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil) {
                fileURLFromItem = fileURL
                suggestedName = fileURL.lastPathComponent
            }
        }

        for type in pasteImageTypes {
            guard let raw = item[type.identifier] else { continue }
            if let data = raw as? Data { return (data, suggestedName) }
            if let image = raw as? UIImage {
                if let data = image.pngData() ?? image.jpegData(compressionQuality: 1.0) {
                    return (data, suggestedName)
                }
            }
        }

        // Some web sources provide only file URL + filename text. Load the image bytes from URL.
        if let fileURLFromItem,
           isLikelyImageFile(url: fileURLFromItem) {
            let accessing = fileURLFromItem.startAccessingSecurityScopedResource()
            defer { if accessing { fileURLFromItem.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: fileURLFromItem),
               UIImage(data: data) != nil {
                return (data, suggestedName)
            }
        }
        return nil
    }

    private func shouldSuppressTextFallback(_ text: String, for item: [String: Any]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid inserting placeholder filename text when clipboard item is image-like.
        if isImageLikePasteboardItem(item) && isLikelyImageFileName(trimmed) {
            return true
        }
        if isImageLikePasteboardItem(item),
           let suggested = suggestedNameFromPasteboardItem(item),
           isLikelyPlaceholderName(trimmed, suggestedName: suggested) {
            return true
        }
        return false
    }

    private func isImageLikePasteboardItem(_ item: [String: Any]) -> Bool {
        for key in item.keys {
            if key == UTType.fileURL.identifier { return true }
            if key == UTType.url.identifier || key == "public.url" {
                if remoteImageURLFromPasteboardItem(item) != nil { return true }
            }
            if let type = UTType(key), type.conforms(to: .image) { return true }
            if key.contains("public.image") || key.contains("png") || key.contains("jpeg") || key.contains("gif") || key.contains("heic") || key.contains("webp") {
                return true
            }
        }
        return false
    }

    private func isLikelyImageFile(url: URL) -> Bool {
        isLikelyImageFileName(url.lastPathComponent)
    }

    private func isLikelyImageFileName(_ text: String) -> Bool {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let exts = [".png", ".jpg", ".jpeg", ".gif", ".heic", ".heif", ".webp", ".tiff", ".bmp"]
        return exts.contains { name.hasSuffix($0) }
    }

    private func remoteImageURLFromPasteboardItem(_ item: [String: Any]) -> (URL, String?)? {
        let raw = item[UTType.url.identifier] ?? item["public.url"]
        guard let raw else { return nil }

        let url: URL?
        if let direct = raw as? URL {
            url = direct
        } else if let string = raw as? String {
            url = URL(string: string)
        } else if let data = raw as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        guard isLikelyRemoteImageURL(url) else { return nil }
        return (url, suggestedNameFromPasteboardItem(item) ?? suggestedFileName(fromRemoteURL: url))
    }

    private func isLikelyRemoteImageURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        let indicators = [".png", ".jpg", ".jpeg", ".gif", ".heic", ".heif", ".webp", ".tiff", ".bmp", "raw=true", "image"]
        return indicators.contains { lower.contains($0) }
    }

    private func suggestedNameFromPasteboardItem(_ item: [String: Any]) -> String? {
        if let raw = item[UTType.fileURL.identifier] {
            if let fileURL = raw as? URL { return fileURL.lastPathComponent }
            if let str = raw as? String, let fileURL = URL(string: str) { return fileURL.lastPathComponent }
            if let data = raw as? Data, let fileURL = URL(dataRepresentation: data, relativeTo: nil) { return fileURL.lastPathComponent }
        }
        if let raw = item[UTType.url.identifier] ?? item["public.url"] {
            let remoteURL: URL?
            if let direct = raw as? URL {
                remoteURL = direct
            } else if let str = raw as? String {
                remoteURL = URL(string: str)
            } else if let data = raw as? Data {
                remoteURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                remoteURL = nil
            }
            guard let remoteURL else { return nil }
            let last = suggestedFileName(fromRemoteURL: remoteURL) ?? remoteURL.lastPathComponent
            if !last.isEmpty { return last }
            if let q = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name.lowercased().contains("filename") })?.value,
               !q.isEmpty {
                return q
            }
        }
        return nil
    }

    private func suggestedFileName(fromRemoteURL url: URL) -> String? {
        let direct = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty, direct != "/" {
            return direct
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let queryItems = components.queryItems ?? []
        let candidates = ["filename", "file", "name", "download", "url", "src"]

        for key in candidates {
            guard let value = queryItems.first(where: { $0.name.lowercased() == key })?.value,
                  !value.isEmpty else { continue }

            if let nestedURL = URL(string: value.removingPercentEncoding ?? value) {
                let nestedName = nestedURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nestedName.isEmpty, nestedName != "/" {
                    return nestedName
                }
            }

            let raw = URL(fileURLWithPath: value).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, raw != "/" {
                return raw
            }
        }
        return nil
    }

    private func isLikelyPlaceholderName(_ text: String, suggestedName: String) -> Bool {
        let normalizedText = text.lowercased()
        let suggestedStem = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent.lowercased()
        if normalizedText == suggestedStem { return true }
        if let prefix = suggestedStem.split(separator: "-").first.map(String.init),
           !prefix.isEmpty,
           normalizedText == prefix {
            return true
        }
        if suggestedStem.hasPrefix(normalizedText), normalizedText.count >= 6 {
            return true
        }
        return false
    }

    // MARK: - Find (programmatic trigger)

    func presentFind(showingReplace: Bool = false) {
        findInteraction?.presentFindNavigator(showingReplace: showingReplace)
    }
}
