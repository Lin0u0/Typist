//
//  KeyboardAccessoryView.swift
//  Typist
//

import UIKit

final class KeyboardAccessoryView: UIInputView {
    private struct SymbolItem {
        let label: String
        let insert: String
    }

    private weak var textView: UITextView?
    var onPhotoButtonTapped: (() -> Void)?

    private let symbols: [SymbolItem] = [
        SymbolItem(label: "⇥", insert: "  "),
        SymbolItem(label: "#", insert: "#"),
        SymbolItem(label: "$", insert: "$"),
        SymbolItem(label: "=", insert: "="),
        SymbolItem(label: "*", insert: "*"),
        SymbolItem(label: "_", insert: "_"),
        SymbolItem(label: "{", insert: "{"),
        SymbolItem(label: "}", insert: "}"),
        SymbolItem(label: "[", insert: "["),
        SymbolItem(label: "]", insert: "]"),
        SymbolItem(label: "(", insert: "("),
        SymbolItem(label: ")", insert: ")"),
        SymbolItem(label: "<", insert: "<"),
        SymbolItem(label: ">", insert: ">"),
        SymbolItem(label: "@", insert: "@"),
        SymbolItem(label: "/", insert: "/"),
    ]

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .default)
        allowsSelfSizing = true
        backgroundColor = .secondarySystemBackground
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for symbol in symbols {
            let button = makeButton(title: symbol.label) { [weak self] in
                InteractionFeedback.selection()
                self?.textView?.insertText(symbol.insert)
            }
            button.accessibilityLabel = L10n.keyboardSymbolAccessibilityLabel(for: symbol.label)
            button.accessibilityHint = L10n.a11yKeyboardInsertHint
            stackView.addArrangedSubview(button)
        }

        scrollView.addSubview(stackView)

        // Separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Photo / Undo / Redo
        let photoButton = makeButton(systemImage: "photo") { [weak self] in
            InteractionFeedback.impact(.light)
            self?.onPhotoButtonTapped?()
        }
        let undoButton = makeButton(systemImage: "arrow.uturn.backward") { [weak self] in
            InteractionFeedback.impact(.light)
            self?.textView?.undoManager?.undo()
        }
        let redoButton = makeButton(systemImage: "arrow.uturn.forward") { [weak self] in
            InteractionFeedback.impact(.light)
            self?.textView?.undoManager?.redo()
        }
        photoButton.accessibilityLabel = L10n.a11yKeyboardPhotoLabel
        photoButton.accessibilityHint = L10n.a11yKeyboardPhotoHint
        undoButton.accessibilityLabel = L10n.a11yKeyboardUndoLabel
        undoButton.accessibilityHint = L10n.a11yKeyboardUndoHint
        redoButton.accessibilityLabel = L10n.a11yKeyboardRedoLabel
        redoButton.accessibilityHint = L10n.a11yKeyboardRedoHint

        let rightStack = UIStackView(arrangedSubviews: [photoButton, undoButton, redoButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 6
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(separator)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            // Right stack anchored to trailing
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Separator between scroll and right stack
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 28),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -8),

            // Scroll view fills remaining space
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Stack inside scroll view
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func makeButton(title: String? = nil, systemImage: String? = nil, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .label
        if let title {
            config.title = title
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var attrs = incoming
                attrs.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
                )
                return attrs
            }
        }
        if let systemImage {
            config.image = UIImage(systemName: systemImage)
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
}
