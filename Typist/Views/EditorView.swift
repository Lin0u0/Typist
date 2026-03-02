//
//  EditorView.swift
//  Typist
//

import SwiftUI

struct EditorView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TypstTextView {
        let textView = TypstTextView()
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: TypstTextView, context: Context) {
        guard textView.text != text else { return }
        textView.text = text
        textView.applyHighlighting()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let typstTextView = textView as? TypstTextView else { return }
            parent.text = textView.text
            typstTextView.applyHighlighting()
        }
    }
}
