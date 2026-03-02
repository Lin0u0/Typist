//
//  TypstTextView.swift
//  Typist
//

import UIKit

final class TypstTextView: UITextView {
    private let highlighter = SyntaxHighlighter()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        autocorrectionType = .no
        autocapitalizationType = .none
        smartDashesType = .no
        smartQuotesType = .no
        spellCheckingType = .no
        backgroundColor = .systemBackground
        textColor = .label
        textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    func applyHighlighting() {
        highlighter.highlight(textStorage)
    }
}
