//
//  SyntaxHighlighter.swift
//  Typist
//

import UIKit

struct SyntaxRule {
    let pattern: String
    let options: NSRegularExpression.Options
    let color: UIColor
    let bold: Bool

    init(pattern: String, options: NSRegularExpression.Options = [], color: UIColor, bold: Bool = false) {
        self.pattern = pattern
        self.options = options
        self.color = color
        self.bold = bold
    }
}

final class SyntaxHighlighter {
    private let baseFont: UIFont
    private let baseColor: UIColor
    private let rules: [SyntaxRule]
    private var compiledRules: [(NSRegularExpression, SyntaxRule)] = []

    init(font: UIFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
         baseColor: UIColor = .label) {
        self.baseFont = font
        self.baseColor = baseColor
        self.rules = [
            // Strings "..."
            SyntaxRule(pattern: #""(?:[^"\\]|\\.)*""#, color: .systemGreen),
            // Headings ^=+ ...
            SyntaxRule(pattern: #"^=+\s.*$"#, options: .anchorsMatchLines, color: .systemBlue, bold: true),
            // Functions #name
            SyntaxRule(pattern: #"#[a-zA-Z_][a-zA-Z0-9_]*"#, color: .systemOrange),
            // Math $...$
            SyntaxRule(pattern: #"\$[^$]*\$"#, color: .systemPurple),
            // Inline code `...`
            SyntaxRule(pattern: #"`[^`]*`"#, color: .systemGray),
            // Labels <label> and references @ref
            SyntaxRule(pattern: #"<[a-zA-Z0-9_:-]+>|@[a-zA-Z_][a-zA-Z0-9_]*"#, color: .systemTeal),
            // Line comments //...
            SyntaxRule(pattern: #"//.*$"#, options: .anchorsMatchLines, color: .systemGray),
        ]
        compiledRules = rules.compactMap { rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                return nil
            }
            return (regex, rule)
        }
    }

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset to base attributes
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: fullRange)

        // Apply syntax rules
        for (regex, rule) in compiledRules {
            let boldFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold)
            regex.enumerateMatches(in: textStorage.string, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                textStorage.addAttribute(.foregroundColor, value: rule.color, range: range)
                if rule.bold {
                    textStorage.addAttribute(.font, value: boldFont, range: range)
                }
            }
        }

        textStorage.endEditing()
    }
}
