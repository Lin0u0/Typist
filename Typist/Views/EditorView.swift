//
//  EditorView.swift
//  Typist
//

import SwiftUI

struct EditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: String?
    @Binding var findRequested: Bool
    var focusCoordinator: EditorFocusCoordinator? = nil
    var theme: EditorTheme = .system
    var onPhotoTapped: () -> Void = {}
    var onImagePasted: (Data) -> Void = { _ in }
    var onRichPaste: ([TypstTextView.PasteFragment]) -> Void = { _ in }

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
        return textView
    }

    func updateUIView(_ textView: TypstTextView, context: Context) {
        focusCoordinator?.register(textView)
        textView.applyTheme(theme)
        textView.accessibilityLabel = L10n.a11yEditorLabel
        textView.accessibilityHint = L10n.a11yEditorHint
        textView.onPhotoButtonTapped = onPhotoTapped
        textView.onImagePasted = onImagePasted
        textView.onRichPaste = onRichPaste

        // Consume pending find request — defer mutation to avoid writing state during view update.
        if findRequested {
            Task { @MainActor in
                textView.presentFind(showingReplace: true)
                self.findRequested = false
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
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView
        weak var textView: TypstTextView?

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
            textView.scheduleHighlighting(.immediate, textChanged: true)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let typstTextView = textView as? TypstTextView else { return }
            parent.text = textView.text
            typstTextView.scheduleHighlighting(.debounced, textChanged: true)
        }
    }
}
