//
//  TypstTextView.swift
//  Typist
//

import UIKit

final class TypstTextView: UITextView {
    private let highlighter = SyntaxHighlighter()
    private(set) var gutterView: LineNumberGutterView!
    private var storedTheme: EditorTheme = .system
    private var appearanceRegistration: (any UITraitChangeRegistration)?

    var onPhotoButtonTapped: (() -> Void)? {
        didSet { (inputAccessoryView as? KeyboardAccessoryView)?.onPhotoButtonTapped = onPhotoButtonTapped }
    }

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
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
        setupGutter()
        setupAccessoryView()
        setupFindInteraction()
        setupAppearanceObservation()
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
            view.applyHighlighting()
        }
    }

    // MARK: - Cmd+F Key Command

    override var keyCommands: [UIKeyCommand]? {
        let findCommand = UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(showFind))
        findCommand.discoverabilityTitle = "Find & Replace"
        return (super.keyCommands ?? []) + [findCommand]
    }

    @objc private func showFind() {
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    // MARK: - Auto-pair Integration

    override func insertText(_ text: String) {
        if AutoPairEngine.handleInsert(text, in: self) {
            applyHighlighting()
            // Notify delegate of change
            delegate?.textViewDidChange?(self)
            return
        }
        super.insertText(text)
    }

    override func deleteBackward() {
        if AutoPairEngine.handleDelete(in: self) {
            applyHighlighting()
            delegate?.textViewDidChange?(self)
            return
        }
        super.deleteBackward()
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
        applyHighlighting()
    }

    // MARK: - Highlighting

    func applyHighlighting() {
        highlighter.highlight(textStorage)
        gutterView.setNeedsDisplay()
    }

    // MARK: - Find (programmatic trigger)

    func presentFind(showingReplace: Bool = false) {
        findInteraction?.presentFindNavigator(showingReplace: showingReplace)
    }
}
