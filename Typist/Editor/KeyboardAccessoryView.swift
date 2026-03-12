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
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 60), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        if #available(iOS 26, *) {
            setupGlassLayout()
        } else {
            setupLegacyLayout()
        }
    }

    // MARK: - iOS 26+ Floating Glass Bar

    @available(iOS 26, *)
    private func setupGlassLayout() {
        // Transparent host — the glass container provides all visuals
        backgroundColor = .clear

        // Glass container
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.clipsToBounds = true
        glass.layer.cornerRadius = 22
        glass.layer.cornerCurve = .continuous
        addSubview(glass)

        // Build content inside the glass
        let (scrollView, rightStack, separator) = buildContent()

        glass.contentView.addSubview(scrollView)
        glass.contentView.addSubview(separator)
        glass.contentView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            // Glass container with horizontal margins, centered vertically
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            // Right stack inside glass
            rightStack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -6),
            rightStack.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),

            // Separator
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 24),
            separator.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),
            separator.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -4),

            // Scroll view
            scrollView.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
        ])
    }

    // MARK: - Pre-iOS 26 Layout

    private func setupLegacyLayout() {
        backgroundColor = .secondarySystemBackground

        let (scrollView, rightStack, separator) = buildContent()

        addSubview(scrollView)
        addSubview(separator)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 28),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -8),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Shared Content

    private func buildContent() -> (scrollView: UIScrollView, rightStack: UIStackView, separator: UIView) {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 2
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
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 36),
        ])

        let separator = UIView()
        separator.backgroundColor = .separator.withAlphaComponent(0.3)
        separator.translatesAutoresizingMaskIntoConstraints = false

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
        rightStack.spacing = 2
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        return (scrollView, rightStack, separator)
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
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return button
    }
}
