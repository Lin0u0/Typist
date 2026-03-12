//
//  EditorView.swift
//  Typist
//

import SwiftUI

struct EditorViewState: Equatable {
    var selectedLocation: Int = 0
    var selectedLength: Int = 0
    var contentOffset: CGPoint = .zero
}

struct EditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: String?
    @Binding var findRequested: Bool
    @Binding var viewState: EditorViewState
    @Binding var cursorJumpOffset: Int?
    var focusCoordinator: EditorFocusCoordinator? = nil
    var sourceMap: SourceMap?
    var syncCoordinator: SyncCoordinator?
    var theme: EditorTheme = .system
    var errorLines: Set<Int> = []
    var onPhotoTapped: () -> Void = {}
    var onImagePasted: (Data) -> Void = { _ in }
    var onRichPaste: ([TypstTextView.PasteFragment]) -> Void = { _ in }
    var fontFamilies: [String] = []
    var bibEntries: [(key: String, type: String)] = []
    var externalLabels: [(name: String, kind: String)] = []
    var imageFiles: [String] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TypstTextView {
        let textView = TypstTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        focusCoordinator?.register(textView)
        textView.applyTheme(theme)
        textView.accessibilityLabel = L10n.a11yEditorLabel
        textView.accessibilityHint = L10n.a11yEditorHint
        textView.accessibilityIdentifier = "editor.text-view"
        context.coordinator.restoreViewStateIfNeeded(in: textView)
        return textView
    }

    func updateUIView(_ textView: TypstTextView, context: Context) {
        focusCoordinator?.register(textView)
        textView.applyTheme(theme)
        textView.setErrorLines(errorLines)
        textView.accessibilityLabel = L10n.a11yEditorLabel
        textView.accessibilityHint = L10n.a11yEditorHint
        textView.onPhotoButtonTapped = onPhotoTapped
        textView.onImagePasted = onImagePasted
        textView.onRichPaste = onRichPaste
        textView.updateFontFamilies(fontFamilies)
        textView.updateBibEntries(bibEntries)
        textView.updateExternalLabels(externalLabels)
        textView.updateImageFiles(imageFiles)

        // Consume pending find request — defer mutation to avoid writing state during view update.
        if findRequested {
            Task { @MainActor in
                textView.presentFind(showingReplace: true)
                self.findRequested = false
            }
        }

        // Consume pending cursor jump request
        if let jumpOffset = cursorJumpOffset {
            let coordinator = context.coordinator
            Task { @MainActor in
                guard self.cursorJumpOffset == jumpOffset else { return }
                self.cursorJumpOffset = nil
                let maxOffset = textView.text.utf16.count
                let safeOffset = min(max(0, jumpOffset), maxOffset)
                textView.selectedRange = NSRange(location: safeOffset, length: 0)
                coordinator.captureViewState(from: textView)
                // Scroll to reveal cursor after layout
                DispatchQueue.main.async {
                    if let range = textView.selectedTextRange {
                        let rect = textView.caretRect(for: range.end).insetBy(dx: 0, dy: -40)
                        textView.scrollRectToVisible(rect, animated: true)
                    }
                }
            }
        }

        // Consume pending insertion request
        if let insertion = insertionRequest {
            let coordinator = context.coordinator
            Task { @MainActor in
                guard self.insertionRequest == insertion else { return }
                self.insertionRequest = nil
                coordinator.insertText(insertion)
            }
            return
        }
        // Never push text back into the view while the user is actively editing.
        // Doing so can dismiss the software keyboard on iPadOS.
        guard !textView.isFirstResponder else { return }
        guard textView.text != text else { return }
        textView.text = text
        textView.scheduleHighlighting(.immediate, textChanged: true)
        context.coordinator.restoreViewStateIfNeeded(in: textView)
    }

    static func dismantleUIView(_ textView: TypstTextView, coordinator: Coordinator) {
        coordinator.captureViewState(from: textView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView
        weak var textView: TypstTextView?
        private var lastAppliedViewState: EditorViewState?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func insertText(_ text: String) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange
            let nsString = textView.text as NSString
            let originalContent = nsString.substring(with: selectedRange)
            let insertedRange = NSRange(location: selectedRange.location, length: (text as NSString).length)

            textView.undoManager?.registerUndo(withTarget: textView) { tv in
                tv.textStorage.replaceCharacters(in: insertedRange, with: originalContent)
                tv.selectedRange = selectedRange
                tv.delegate?.textViewDidChange?(tv)
            }
            textView.undoManager?.setActionName(L10n.tr("action.insert_image"))

            textView.textStorage.replaceCharacters(in: selectedRange, with: text)
            textView.selectedRange = NSRange(location: selectedRange.location + insertedRange.length, length: 0)
            parent.text = textView.text
            captureViewState(from: textView)
            textView.scheduleHighlighting(.immediate, textChanged: true)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let typstTextView = textView as? TypstTextView else { return }
            parent.text = textView.text
            captureViewState(from: typstTextView)
            typstTextView.scheduleHighlighting(.debounced, textChanged: true)
            typstTextView.updateCompletion()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let typstTextView = textView as? TypstTextView else { return }
            captureViewState(from: typstTextView)
            // After a tap-to-dismiss, skip re-triggering completion for this selection change
            if typstTextView.consumeSelectionSuppression() { return }
            typstTextView.updateCompletion()
            syncCursorToPreview(textView)
        }

        private func syncCursorToPreview(_ textView: UITextView) {
            guard let syncCoordinator = parent.syncCoordinator,
                  let sourceMap = parent.sourceMap,
                  !sourceMap.isEmpty else { return }
            guard syncCoordinator.beginSync(.editorToPreview) else { return }

            let cursorLocation = textView.selectedRange.location
            let text = textView.text as NSString
            // Count newlines up to cursor to get 1-based line number.
            let prefix = cursorLocation <= text.length
                ? text.substring(to: cursorLocation)
                : textView.text ?? ""
            let line = prefix.components(separatedBy: "\n").count

            if let target = sourceMap.pdfPosition(forLine: line) {
                syncCoordinator.previewScrollTarget = PreviewScrollTarget(
                    page: target.page,
                    yPoints: target.yPoints
                )
            }
            syncCoordinator.endSync()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only dismiss on user-initiated scrolls (drag/momentum), not on auto-scroll from typing
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            guard let typstTextView = scrollView as? TypstTextView else { return }
            captureViewState(from: typstTextView)
            typstTextView.dismissCompletion()
        }

        func captureViewState(from textView: TypstTextView) {
            let newState = EditorViewState(
                selectedLocation: textView.selectedRange.location,
                selectedLength: textView.selectedRange.length,
                contentOffset: textView.contentOffset
            )
            guard parent.viewState != newState else { return }
            parent.viewState = newState
        }

        func restoreViewStateIfNeeded(in textView: TypstTextView) {
            guard lastAppliedViewState != parent.viewState else { return }

            let utf16Count = textView.text.utf16.count
            let location = min(parent.viewState.selectedLocation, utf16Count)
            let length = min(parent.viewState.selectedLength, max(utf16Count - location, 0))
            let restoredRange = NSRange(location: location, length: length)

            if textView.selectedRange != restoredRange {
                textView.selectedRange = restoredRange
            }

            if textView.contentOffset != parent.viewState.contentOffset {
                textView.setContentOffset(parent.viewState.contentOffset, animated: false)
            }

            lastAppliedViewState = parent.viewState
        }
    }
}
