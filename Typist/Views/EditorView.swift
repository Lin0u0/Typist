//
//  EditorView.swift
//  Typist
//

import SwiftUI

struct EditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TypstTextView {
        let textView = TypstTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: TypstTextView, context: Context) {
        // Consume pending insertion request
        if let insertion = insertionRequest {
            // Defer to avoid mutating state during view update
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                coordinator.insertText(insertion)
                self.insertionRequest = nil
            }
            return
        }
        guard textView.text != text else { return }
        textView.text = text
        textView.applyHighlighting()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView
        weak var textView: TypstTextView?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func insertText(_ text: String) {
            guard let textView else { return }
            let range = textView.selectedRange
            textView.textStorage.replaceCharacters(in: range, with: text)
            textView.selectedRange = NSRange(location: range.location + text.count, length: 0)
            textView.applyHighlighting()
            parent.text = textView.text
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let typstTextView = textView as? TypstTextView else { return }
            parent.text = textView.text
            typstTextView.applyHighlighting()
        }
    }
}
