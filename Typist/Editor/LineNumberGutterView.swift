//
//  LineNumberGutterView.swift
//  Typist
//

import UIKit

final class LineNumberGutterView: UIView {

    private static let gutterFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let minGutterWidth: CGFloat = 36

    private weak var textView: UITextView?
    private var gutterBgColor: UIColor = .secondarySystemBackground
    private var gutterFgColor: UIColor = .secondaryLabel
    private var lineStartOffsets: [Int] = [0]
    private var cachedGutterWidth: CGFloat = LineNumberGutterView.minGutterWidth
    private var needsLineMetricsRefresh = true

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    func applyTheme(_ theme: EditorTheme) {
        gutterBgColor = theme.gutterBackground
        gutterFgColor = theme.gutterForeground
        setNeedsDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func textDidChange() {
        needsLineMetricsRefresh = true
        setNeedsDisplay()
    }

    var gutterWidth: CGFloat {
        refreshLineMetricsIfNeeded()
        return cachedGutterWidth
    }

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        refreshLineMetricsIfNeeded()

        // Resolve dynamic UIColors against the current trait collection before converting to CGColor.
        let resolvedBg = gutterBgColor.resolvedColor(with: traitCollection)
        let resolvedFg = gutterFgColor.resolvedColor(with: traitCollection)

        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(resolvedBg.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.gutterFont,
            .foregroundColor: resolvedFg,
        ]

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.bounds, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsString = textView.text as NSString
        let firstVisibleLineIndex = lineIndex(forCharacterOffset: visibleCharRange.location)
        var lineIndex = firstVisibleLineIndex
        let visibleEnd = NSMaxRange(visibleCharRange)

        func caretRectForOffset(_ offset: Int) -> CGRect? {
            let clampedOffset = min(max(offset, 0), nsString.length)
            guard let position = textView.position(from: textView.beginningOfDocument, offset: clampedOffset) else {
                return nil
            }
            return textView.caretRect(for: position)
        }

        while lineIndex < lineStartOffsets.count {
            let offset = lineStartOffsets[lineIndex]
            if offset > visibleEnd && lineIndex != firstVisibleLineIndex {
                break
            }

            guard let startCaretRect = caretRectForOffset(offset) else {
                break
            }

            let numberString = "\(lineIndex + 1)" as NSString
            let stringSize = numberString.size(withAttributes: attributes)
            let drawPoint = CGPoint(
                x: gutterWidth - stringSize.width - 8,
                y: startCaretRect.minY + (max(startCaretRect.height, Self.gutterFont.lineHeight) - stringSize.height) / 2
            )
            numberString.draw(at: drawPoint, withAttributes: attributes)

            lineIndex += 1
        }
    }

    private func refreshLineMetricsIfNeeded() {
        guard needsLineMetricsRefresh, let textView else { return }

        let nsString = textView.text as NSString
        let length = nsString.length
        var starts = [0]
        var index = 0

        while index < length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex < length {
                starts.append(nextIndex)
            } else if nextIndex == length, length > 0, nsString.character(at: length - 1) == 10 {
                starts.append(length)
            }

            guard nextIndex > index else { break }
            index = nextIndex
        }

        lineStartOffsets = starts

        let digits = String(max(starts.count, 1)).count
        let sampleString = String(repeating: "8", count: max(digits, 2)) as NSString
        let size = sampleString.size(withAttributes: [.font: Self.gutterFont])
        cachedGutterWidth = max(ceil(size.width) + 16, Self.minGutterWidth)
        needsLineMetricsRefresh = false
    }

    private func lineIndex(forCharacterOffset offset: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 0 }

        var lowerBound = 0
        var upperBound = lineStartOffsets.count

        while lowerBound < upperBound {
            let mid = (lowerBound + upperBound) / 2
            if lineStartOffsets[mid] <= offset {
                lowerBound = mid + 1
            } else {
                upperBound = mid
            }
        }

        return max(0, lowerBound - 1)
    }
}
