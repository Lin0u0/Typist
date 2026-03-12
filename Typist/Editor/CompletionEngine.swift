//
//  CompletionEngine.swift
//  Typist
//

import UIKit

struct CompletionItem {
    let label: String
    let insertText: String?
    let kind: Kind
    let detail: String?

    enum Kind {
        case keyword
        case function
        case snippet
        case parameter
        case value
        case reference
    }

    var isInsertable: Bool {
        insertText != nil
    }
}

final class CompletionEngine {
    static let shared = CompletionEngine()

    private let items: [CompletionItem] = {
        var all: [CompletionItem] = []

        // Keywords
        let keywords = [
            ("let", "let "),
            ("set", "set "),
            ("show", "show "),
            ("import", "import "),
            ("include", "include "),
            ("if", "if "),
            ("else", "else "),
            ("for", "for "),
            ("while", "while "),
            ("return", "return"),
            ("break", "break"),
            ("continue", "continue"),
        ]
        for (name, insert) in keywords {
            all.append(CompletionItem(label: name, insertText: insert, kind: .keyword, detail: "keyword"))
        }

        // Common functions
        let functions: [(String, String, String?)] = [
            // Text & content
            ("text", "text()", "Set text properties"),
            ("emph", "emph[]", "Emphasize content"),
            ("strong", "strong[]", "Bold content"),
            ("heading", "heading[]", "Section heading"),
            ("par", "par[]", "Paragraph"),
            ("raw", "raw(\"\")", "Raw text / code"),
            ("link", "link(\"\")", "Hyperlink"),
            ("footnote", "footnote[]", "Footnote"),
            ("cite", "cite(<>)", "Citation"),
            ("ref", "ref(<>)", "Reference"),
            ("highlight", "highlight[]", "Highlight text"),
            ("overline", "overline[]", "Overline"),
            ("underline", "underline[]", "Underline"),
            ("strike", "strike[]", "Strikethrough"),
            ("smallcaps", "smallcaps[]", "Small capitals"),
            ("sub", "sub[]", "Subscript"),
            ("super", "super[]", "Superscript"),
            ("lorem", "lorem()", "Placeholder text"),

            // Layout
            ("page", "page()", "Page settings"),
            ("align", "align()[]", "Alignment"),
            ("pad", "pad()[]", "Padding"),
            ("block", "block[]", "Block-level container"),
            ("box", "box[]", "Inline container"),
            ("stack", "stack()[]", "Stack layout"),
            ("grid", "grid()", "Grid layout"),
            ("columns", "columns()[]", "Multi-column layout"),
            ("place", "place()[]", "Absolute placement"),
            ("move", "move()[]", "Move content"),
            ("rotate", "rotate()[]", "Rotate content"),
            ("scale", "scale()[]", "Scale content"),
            ("hide", "hide[]", "Hidden content"),
            ("v", "v()", "Vertical spacing"),
            ("h", "h()", "Horizontal spacing"),
            ("colbreak", "colbreak()", "Column break"),
            ("pagebreak", "pagebreak()", "Page break"),
            ("parbreak", "parbreak()", "Paragraph break"),
            ("linebreak", "linebreak()", "Line break"),

            // Media
            ("image", "image(\"\")", "Include image"),
            ("figure", "figure()[]", "Figure with caption"),
            ("table", "table()", "Table"),
            ("list", "list[]", "Bullet list"),
            ("enum", "enum[]", "Numbered list"),
            ("terms", "terms[]", "Term list"),
            ("outline", "outline()", "Table of contents"),
            ("bibliography", "bibliography(\"\")", "Bibliography"),
            ("line", "line()", "Draw a line"),
            ("rect", "rect[]", "Rectangle"),
            ("circle", "circle[]", "Circle"),
            ("ellipse", "ellipse[]", "Ellipse"),
            ("polygon", "polygon()", "Polygon"),
            ("path", "path()", "Bézier path"),

            // Data & logic
            ("numbering", "numbering(\"\")", "Numbering pattern"),
            ("counter", "counter()", "Counter"),
            ("state", "state(\"\")", "Stateful value"),
            ("locate", "locate()[]", "Locate in document"),
            ("query", "query()", "Query elements"),
            ("measure", "measure()[]", "Measure content"),
            ("layout", "layout()[]", "Layout callback"),
            ("datetime", "datetime()", "Date/time"),
            ("duration", "duration()", "Duration"),

            // Color
            ("rgb", "rgb(\"\")", "RGB color"),
            ("luma", "luma()", "Grayscale color"),
            ("cmyk", "cmyk()", "CMYK color"),
            ("color", "color", "Color type"),
            ("gradient", "gradient", "Gradient"),
            ("pattern", "pattern()[]", "Tiling pattern"),
            ("stroke", "stroke()", "Stroke style"),

            // Document
            ("document", "document()", "Document metadata"),
            ("context", "context ", "Context expression"),
        ]
        for (name, insert, detail) in functions {
            all.append(CompletionItem(label: name, insertText: insert, kind: .function, detail: detail))
        }

        return all.sorted { $0.label < $1.label }
    }()

    // MARK: - Parameter Database

    /// Maps function name → list of (paramName, detail) pairs.
    private let parameterDB: [String: [(String, String?)]] = [
        // Text & content
        "text": [
            ("font", "Font family"), ("size", "Font size"), ("weight", "Font weight"),
            ("style", "Font style"), ("fill", "Text color"), ("lang", "Language"),
            ("region", "Region"), ("dir", "Text direction"), ("hyphenate", "Allow hyphenation"),
            ("tracking", "Letter spacing"), ("spacing", "Word spacing"),
            ("baseline", "Baseline shift"), ("top-edge", "Top edge metric"),
            ("bottom-edge", "Bottom edge metric"), ("overhang", "Overhang"),
            ("kerning", "Kerning"), ("alternates", "Alternates"),
            ("stylistic-set", "Stylistic set"), ("ligatures", "Ligatures"),
            ("discretionary-ligatures", "Discretionary ligatures"),
            ("historical-ligatures", "Historical ligatures"),
            ("number-type", "Number type"), ("number-width", "Number width"),
            ("slashed-zero", "Slashed zero"), ("fractions", "Fractions"),
            ("features", "OpenType features"),
        ],
        "heading": [
            ("level", "Heading level 1–6"), ("numbering", "Numbering pattern"),
            ("supplement", "Supplement"), ("outlined", "Show in outline"),
            ("bookmarked", "Add bookmark"), ("hanging-indent", "Hanging indent"),
            ("depth", "Depth"),
        ],
        "par": [
            ("leading", "Line spacing"), ("justify", "Justify text"),
            ("linebreaks", "Line break algorithm"), ("first-line-indent", "First line indent"),
            ("hanging-indent", "Hanging indent"), ("spacing", "Paragraph spacing"),
        ],
        "raw": [
            ("lang", "Language"), ("block", "Block display"), ("theme", "Syntax theme"),
            ("tab-size", "Tab size"), ("align", "Alignment"),
        ],
        "link": [("dest", "Destination URL")],
        "strong": [("delta", "Weight delta")],
        "highlight": [
            ("fill", "Fill color"), ("stroke", "Stroke"), ("extent", "Extent"),
            ("radius", "Corner radius"),
        ],
        "strike": [
            ("stroke", "Stroke style"), ("offset", "Vertical offset"),
            ("extent", "Horizontal extent"), ("background", "Behind text"),
        ],
        "underline": [
            ("stroke", "Stroke style"), ("offset", "Vertical offset"),
            ("extent", "Horizontal extent"), ("evade", "Evade descenders"),
            ("background", "Behind text"),
        ],
        "overline": [
            ("stroke", "Stroke style"), ("offset", "Vertical offset"),
            ("extent", "Horizontal extent"), ("evade", "Evade ascenders"),
            ("background", "Behind text"),
        ],
        "sub": [("typographic", "Use OpenType"), ("baseline", "Baseline shift"), ("size", "Size")],
        "super": [("typographic", "Use OpenType"), ("baseline", "Baseline shift"), ("size", "Size")],
        "lorem": [("words", "Word count")],

        // Layout
        "page": [
            ("paper", "Paper size"), ("width", "Page width"), ("height", "Page height"),
            ("margin", "Margins"), ("binding", "Binding side"),
            ("columns", "Column count"), ("fill", "Background fill"),
            ("numbering", "Page numbering"), ("number-align", "Number alignment"),
            ("header", "Header content"), ("footer", "Footer content"),
            ("header-ascent", "Header ascent"), ("footer-descent", "Footer descent"),
            ("foreground", "Foreground layer"), ("background", "Background layer"),
        ],
        "align": [
            ("alignment", "center / left / right / top / bottom"),
        ],
        "pad": [
            ("left", "Left padding"), ("right", "Right padding"),
            ("top", "Top padding"), ("bottom", "Bottom padding"),
            ("x", "Horizontal padding"), ("y", "Vertical padding"),
            ("rest", "Remaining sides"),
        ],
        "block": [
            ("width", "Width"), ("height", "Height"), ("fill", "Background fill"),
            ("stroke", "Border stroke"), ("radius", "Corner radius"),
            ("inset", "Inner padding"), ("outset", "Outer expansion"),
            ("spacing", "Surrounding spacing"), ("above", "Space above"),
            ("below", "Space below"), ("breakable", "Allow page break"),
            ("clip", "Clip content"), ("sticky", "Sticky"),
        ],
        "box": [
            ("width", "Width"), ("height", "Height"), ("fill", "Background fill"),
            ("stroke", "Border stroke"), ("radius", "Corner radius"),
            ("inset", "Inner padding"), ("outset", "Outer expansion"),
            ("baseline", "Baseline"), ("clip", "Clip content"),
        ],
        "stack": [("dir", "Stack direction"), ("spacing", "Item spacing")],
        "grid": [
            ("columns", "Column definitions"), ("rows", "Row definitions"),
            ("gutter", "Gutter size"), ("column-gutter", "Column gutter"),
            ("row-gutter", "Row gutter"), ("fill", "Cell fill"),
            ("align", "Cell alignment"), ("stroke", "Cell stroke"),
            ("inset", "Cell inset"),
        ],
        "columns": [("count", "Number of columns"), ("gutter", "Column gutter")],
        "place": [
            ("alignment", "Placement"), ("dx", "Horizontal offset"),
            ("dy", "Vertical offset"), ("float", "Float placement"),
            ("clearance", "Clearance"), ("scope", "Scope"),
        ],
        "move": [("dx", "Horizontal offset"), ("dy", "Vertical offset")],
        "rotate": [("angle", "Rotation angle"), ("origin", "Transform origin"), ("reflow", "Reflow")],
        "scale": [
            ("factor", "Scale factor (e.g. 50%)"),
            ("x", "Horizontal scale"), ("y", "Vertical scale"),
            ("origin", "Transform origin"), ("reflow", "Reflow"),
        ],
        "v": [("amount", "Spacing amount"), ("weak", "Weak spacing")],
        "h": [("amount", "Spacing amount"), ("weak", "Weak spacing")],

        // Media
        "image": [
            ("source", "Image path"), ("width", "Width"), ("height", "Height"),
            ("alt", "Alt text"), ("fit", "Fit mode: cover/contain/stretch"),
            ("format", "Image format"),
        ],
        "figure": [
            ("caption", "Caption"), ("supplement", "Supplement"),
            ("numbering", "Numbering"), ("placement", "Placement: auto/top/bottom"),
            ("gap", "Gap between body and caption"), ("outlined", "Show in outline"),
            ("kind", "Figure kind"),
        ],
        "table": [
            ("columns", "Column definitions"), ("rows", "Row definitions"),
            ("gutter", "Gutter size"), ("column-gutter", "Column gutter"),
            ("row-gutter", "Row gutter"), ("fill", "Cell fill"),
            ("align", "Cell alignment"), ("stroke", "Cell stroke"),
            ("inset", "Cell inset"),
        ],
        "list": [
            ("marker", "Bullet marker"), ("indent", "Indent"),
            ("body-indent", "Body indent"), ("spacing", "Item spacing"),
            ("tight", "Tight spacing"),
        ],
        "enum": [
            ("numbering", "Numbering pattern"), ("start", "Start number"),
            ("full", "Full numbering"), ("indent", "Indent"),
            ("body-indent", "Body indent"), ("spacing", "Item spacing"),
            ("tight", "Tight spacing"),
        ],
        "terms": [
            ("separator", "Separator"), ("indent", "Indent"),
            ("hanging-indent", "Hanging indent"), ("spacing", "Item spacing"),
            ("tight", "Tight spacing"),
        ],
        "outline": [
            ("title", "Outline title"), ("target", "Target selector"),
            ("depth", "Max depth"), ("indent", "Indentation"),
            ("fill", "Fill between entry and page"),
        ],
        "bibliography": [
            ("path", "Bibliography file"), ("title", "Title"),
            ("style", "Citation style"), ("full", "Show all entries"),
        ],
        "line": [
            ("length", "Line length"), ("angle", "Angle"),
            ("start", "Start point"), ("end", "End point"),
            ("stroke", "Stroke style"),
        ],
        "rect": [
            ("width", "Width"), ("height", "Height"), ("fill", "Fill color"),
            ("stroke", "Stroke"), ("radius", "Corner radius"),
            ("inset", "Inner padding"),
        ],
        "circle": [
            ("radius", "Circle radius"), ("fill", "Fill color"),
            ("stroke", "Stroke"), ("inset", "Inner padding"),
        ],
        "ellipse": [
            ("width", "Width"), ("height", "Height"), ("fill", "Fill color"),
            ("stroke", "Stroke"), ("inset", "Inner padding"),
        ],
        "polygon": [
            ("vertices", "Vertex points"), ("fill", "Fill color"),
            ("stroke", "Stroke"),
        ],

        // Data & logic
        "numbering": [("pattern", "Numbering pattern")],
        "counter": [("key", "Counter key")],
        "state": [("key", "State key"), ("init", "Initial value")],
        "datetime": [
            ("year", "Year"), ("month", "Month"), ("day", "Day"),
            ("hour", "Hour"), ("minute", "Minute"), ("second", "Second"),
        ],
        "duration": [
            ("weeks", "Weeks"), ("days", "Days"), ("hours", "Hours"),
            ("minutes", "Minutes"), ("seconds", "Seconds"),
        ],

        // Color
        "rgb": [("hex", "Hex string or r,g,b,a")],
        "luma": [("lightness", "Lightness 0–255")],
        "cmyk": [
            ("cyan", "Cyan 0%–100%"), ("magenta", "Magenta"),
            ("yellow", "Yellow"), ("key", "Key/black"),
        ],
        "stroke": [
            ("paint", "Stroke color"), ("thickness", "Thickness"),
            ("cap", "Line cap: butt/round/square"), ("join", "Line join: miter/round/bevel"),
            ("dash", "Dash pattern"), ("miter-limit", "Miter limit"),
        ],

        // Document
        "document": [
            ("title", "Document title"), ("author", "Author"),
            ("keywords", "Keywords"), ("date", "Date"),
        ],
    ]

    /// Result type that distinguishes `#function` completions from parameter completions.
    enum CompletionContext {
        /// Completing after `#` — prefix includes the `#`.
        case hashPrefix(prefix: String, items: [CompletionItem])
        /// Completing a parameter name inside `funcname(...)` — prefix is the partial param name typed.
        case parameter(prefix: String, items: [CompletionItem])
        /// Completing a parameter value after `paramName:` — prefix is the partial value typed (without quotes).
        case value(prefix: String, isQuoted: Bool, items: [CompletionItem])
        /// Completing after `@` — cross-references and citations.
        case atPrefix(prefix: String, items: [CompletionItem])
        /// Completing inside `<>` for `#cite(<>)` or `#ref(<>)`.
        case angleBracket(prefix: String, items: [CompletionItem])
    }

    // MARK: - Dynamic Data (set from outside)

    /// Available font family names for value completion.
    var fontFamilies: [String] = []

    /// BibTeX citation keys with their entry type (e.g. "article", "book").
    var bibEntries: [(key: String, type: String)] = []

    /// Labels defined in other project files (not the current editor text).
    var externalLabels: [(name: String, kind: String)] = []

    /// Image file paths relative to the project root, for path completion inside `image("")`.
    var imageFiles: [String] = []

    /// Typst font weight names.
    private let weightValues: [(String, String)] = [
        ("thin", "100"), ("extralight", "200"), ("light", "300"),
        ("regular", "400"), ("medium", "500"), ("semibold", "600"),
        ("bold", "700"), ("extrabold", "800"), ("black", "900"),
    ]

    /// Maps (paramName) → static value suggestions. Font is handled dynamically.
    private let staticValueDB: [String: [(String, String?)]] = [
        "paper": [
            ("a0", "841 × 1189 mm"), ("a1", "594 × 841 mm"), ("a2", "420 × 594 mm"),
            ("a3", "297 × 420 mm"), ("a4", "210 × 297 mm"), ("a5", "148 × 210 mm"),
            ("a6", "105 × 148 mm"), ("us-letter", "8.5 × 11 in"), ("us-legal", "8.5 × 14 in"),
        ],
        "fit": [("cover", "Fill area, crop if needed"), ("contain", "Fit within bounds"), ("stretch", "Stretch to fill")],
        "format": [("png", nil), ("jpg", nil), ("gif", nil), ("svg", nil)],
        "linebreaks": [("simple", "Simple algorithm"), ("optimized", "Knuth-Plass algorithm")],
        "cap": [("butt", "Flat cap"), ("round", "Round cap"), ("square", "Square cap")],
        "join": [("miter", "Sharp corner"), ("round", "Round corner"), ("bevel", "Flat corner")],
        "dash": [("solid", nil), ("dotted", nil), ("dashed", nil), ("dash-dotted", nil), ("loosely-dashed", nil), ("densely-dashed", nil)],
        "numbering": [("1", "Arabic"), ("a", "Lowercase letter"), ("A", "Uppercase letter"), ("i", "Lowercase roman"), ("I", "Uppercase roman"), ("*", "Symbol footnotes")],
        "supplement": [("auto", "Automatic")],
    ]

    /// Maps function name → paramName → context-specific value hints.
    private let contextualValueDB: [String: [String: [(String, String?)]]] = [
        "text": [
            "style": [("normal", "Upright"), ("italic", "Italic"), ("oblique", "Oblique")],
            "dir": [("ltr", "Left to right"), ("rtl", "Right to left")],
            "number-type": [("lining", "Lining numerals"), ("old-style", "Old-style numerals")],
            "number-width": [("proportional", "Variable width"), ("tabular", "Fixed width")],
        ],
        "bibliography": [
            "style": [
                ("ieee", "Engineering / IT"),
                ("apa", "Psychology / life sciences"),
                ("mla", "Humanities"),
                ("chicago-author-date", "Chicago author-date"),
                ("chicago-notes", "Chicago notes and bibliography"),
                ("harvard-cite-them-right", "Harvard"),
                ("american-physics-society", "Physics"),
                ("vancouver", "Medical / scientific"),
                ("gb-7714-2015-numeric", "GB/T 7714 numeric"),
                ("gb-7714-2015-author-date", "GB/T 7714 author-date"),
            ],
        ],
        "stack": [
            "dir": [("ltr", "Left to right"), ("rtl", "Right to left"), ("ttb", "Top to bottom"), ("btt", "Bottom to top")],
        ],
        "figure": [
            "placement": [("auto", "Automatic"), ("top", "Top of page"), ("bottom", "Bottom of page"), ("none", "Inline")],
            "kind": [("image", "Image figure"), ("table", "Table figure"), ("raw", "Code figure")],
            "scope": [("column", "Current column"), ("parent", "Full page")],
        ],
        "place": [
            "alignment": [
                ("left", nil), ("center", nil), ("right", nil),
                ("top", nil), ("bottom", nil),
                ("top + left", nil), ("top + right", nil),
                ("center + horizon", nil),
                ("bottom + left", nil), ("bottom + right", nil),
            ],
            "scope": [("column", "Current column"), ("parent", "Full page")],
        ],
        "grid": [
            "align": [
                ("left", nil), ("center", nil), ("right", nil),
                ("top", nil), ("bottom", nil), ("horizon", nil),
            ],
        ],
        "table": [
            "align": [
                ("left", nil), ("center", nil), ("right", nil),
                ("top", nil), ("bottom", nil), ("horizon", nil),
            ],
        ],
        "page": [
            "binding": [("left", nil), ("right", nil)],
            "number-align": [
                ("left", nil), ("center", nil), ("right", nil),
                ("top", nil), ("bottom", nil),
            ],
        ],
        "raw": [
            "align": [("left", nil), ("center", nil), ("right", nil)],
        ],
    ]

    /// Parameters listed here are shown as signature hints but should not be inserted as named args.
    /// These are positional parameters that the user should type directly without `name: `.
    private let hintOnlyParameters: [String: Set<String>] = [
        "align": ["alignment"],
        "bibliography": ["path"],
        "cmyk": ["cyan", "magenta", "yellow", "key"],
        "columns": ["count"],
        "counter": ["key"],
        "h": ["amount"],
        "image": ["source"],
        "link": ["dest"],
        "lorem": ["words"],
        "luma": ["lightness"],
        "numbering": ["pattern"],
        "place": ["alignment"],
        "rgb": ["hex"],
        "rotate": ["angle"],
        "scale": ["factor"],
        "state": ["key"],
        "v": ["amount"],
    ]

    /// Values to suggest at positional argument positions (after `(` or `,`).
    /// Tuples: (label, insertText or nil for hint-only, detail).
    private let positionalValueDB: [String: [(String, String?, String?)]] = [
        "align": [
            ("left", "left", "Left"), ("center", "center", "Center"), ("right", "right", "Right"),
            ("top", "top", "Top"), ("bottom", "bottom", "Bottom"),
            ("horizon", "horizon", "Horizontal center"),
            ("start", "start", "Script direction start"), ("end", "end", "Script direction end"),
            ("left + top", "left + top", nil), ("center + horizon", "center + horizon", nil),
        ],
        "place": [
            ("left", "left", nil), ("center", "center", nil), ("right", "right", nil),
            ("top", "top", nil), ("bottom", "bottom", nil),
            ("top + left", "top + left", nil), ("top + right", "top + right", nil),
            ("center + horizon", "center + horizon", nil),
            ("bottom + left", "bottom + left", nil), ("bottom + right", "bottom + right", nil),
        ],
        "v": [
            ("em", nil, "Relative to font size"), ("pt", nil, "Points (1/72 in)"),
            ("mm", nil, "Millimeters"), ("cm", nil, "Centimeters"), ("in", nil, "Inches"),
            ("%", nil, "Percentage"), ("fr", nil, "Fractional unit"),
        ],
        "h": [
            ("em", nil, "Relative to font size"), ("pt", nil, "Points (1/72 in)"),
            ("mm", nil, "Millimeters"), ("cm", nil, "Centimeters"), ("in", nil, "Inches"),
            ("%", nil, "Percentage"), ("fr", nil, "Fractional unit"),
        ],
        "rotate": [
            ("deg", nil, "Degrees"), ("rad", nil, "Radians"), ("turn", nil, "Turns (360° = 1turn)"),
        ],
        "columns": [
            ("2", "2", nil), ("3", "3", nil), ("4", "4", nil),
        ],
        "rgb": [
            ("#000000", "#000000", "Black"), ("#ffffff", "#ffffff", "White"),
            ("#ff0000", "#ff0000", "Red"), ("#00ff00", "#00ff00", "Green"), ("#0000ff", "#0000ff", "Blue"),
        ],
        "luma": [
            ("0", "0", "Black"), ("128", "128", "Mid-gray"), ("255", "255", "White"),
        ],
        "counter": [
            ("heading", "heading", "Heading counter"), ("page", "page", "Page counter"),
            ("figure", "figure", "Figure counter"), ("footnote", "footnote", "Footnote counter"),
        ],
    ]

    // MARK: - Public API

    /// Returns completion context for the given cursor position, or nil if none.
    func completions(for text: String, cursorOffset: Int) -> CompletionContext? {
        guard cursorOffset > 0, cursorOffset <= text.count else { return nil }

        // Try image/file path completion (inside `image("...")` etc.)
        if let pathResult = pathCompletions(for: text, cursorOffset: cursorOffset) {
            return pathResult
        }

        // Try value completion first (highest priority when after `param:`)
        if let valueResult = valueCompletions(for: text, cursorOffset: cursorOffset) {
            return valueResult
        }

        // Try parameter completion (when inside parens)
        if let paramResult = parameterCompletions(for: text, cursorOffset: cursorOffset) {
            return paramResult
        }

        // Try `@` reference completion
        if let refResult = referenceCompletions(for: text, cursorOffset: cursorOffset) {
            return refResult
        }

        // Try `<>` angle-bracket completion inside cite()/ref()
        if let abResult = angleBracketCompletions(for: text, cursorOffset: cursorOffset) {
            return abResult
        }

        // Fall back to `#` prefix completion
        let utf16 = text.utf16
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        var start = cursorIndex
        while start > utf16.startIndex {
            let prev = utf16.index(before: start)
            let ch = text[prev]
            if ch == "#" {
                let prefix = String(text[prev..<cursorIndex])
                let query = String(prefix.dropFirst())
                let filtered = query.isEmpty ? items : items.filter { $0.label.hasPrefix(query) }
                guard !filtered.isEmpty else { return nil }
                if filtered.count == 1, filtered[0].label == query { return nil }
                return .hashPrefix(prefix: prefix, items: filtered)
            } else if ch.isLetter || ch == "_" || ch == "-" || ch.isNumber {
                start = prev
                continue
            } else {
                break
            }
        }
        return nil
    }

    // MARK: - Path Completion (image/include/import)

    /// Functions whose first positional string argument is a file path.
    private static let pathFunctions: Set<String> = ["image", "figure", "bibliography", "csv", "json", "toml", "yaml", "xml", "read"]

    /// Detects cursor inside a quoted string that is a positional or `source:`/`path:` argument
    /// of a path-accepting function, and suggests matching project files.
    private func pathCompletions(for text: String, cursorOffset: Int) -> CompletionContext? {
        let utf16 = text.utf16
        guard cursorOffset > 0, cursorOffset <= utf16.count else { return nil }
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        // Walk backwards from cursor to find the opening `"`
        var probe = cursorIndex
        var quotePos: String.Index?
        while probe > utf16.startIndex {
            let prev = utf16.index(before: probe)
            let ch = text[prev]
            if ch == "\"" {
                quotePos = prev
                break
            }
            // Stop at newline or closing quote (means we're not inside a string)
            if ch == "\n" || ch == "\r" { return nil }
            probe = prev
        }
        guard let openQuote = quotePos else { return nil }

        // The typed path so far (between opening `"` and cursor)
        let valueStart = utf16.index(after: openQuote)
        let typedPath = String(text[valueStart..<cursorIndex])

        // From the `"`, determine context: is this inside a path-accepting function?
        // Walk backwards from `"` skipping whitespace to check what precedes it.
        var scan = openQuote
        while scan > utf16.startIndex {
            let prev = utf16.index(before: scan)
            let ch = text[prev]
            if ch == " " || ch == "\t" { scan = prev; continue }
            break
        }

        // Check for `paramName: "` pattern — accept `source:` or `path:`
        var isNamedPathParam = false
        if scan > utf16.startIndex {
            let charBefore = text[utf16.index(before: scan)]
            if charBefore == ":" {
                // Extract param name before `:`
                let colonPos = utf16.index(before: scan)
                var paramEnd = colonPos
                while paramEnd > utf16.startIndex {
                    let prev = utf16.index(before: paramEnd)
                    if text[prev] == " " || text[prev] == "\t" { paramEnd = prev } else { break }
                }
                var paramStart = paramEnd
                while paramStart > utf16.startIndex {
                    let prev = utf16.index(before: paramStart)
                    let c = text[prev]
                    if c.isLetter || c == "-" || c == "_" || c.isNumber { paramStart = prev } else { break }
                }
                if paramStart < paramEnd {
                    let paramName = String(text[paramStart..<paramEnd])
                    if paramName == "source" || paramName == "path" {
                        isNamedPathParam = true
                    }
                }
            }
        }

        // Check for positional argument: `("`  or  `, "`
        var isPositional = false
        if !isNamedPathParam, scan > utf16.startIndex {
            let charBefore = text[utf16.index(before: scan)]
            if charBefore == "(" || charBefore == "," {
                isPositional = true
            }
        }

        guard isNamedPathParam || isPositional else { return nil }

        // Determine the enclosing function name
        guard let funcName = findEnclosingFunctionName(in: text, beforeOffset: cursorOffset),
              Self.pathFunctions.contains(funcName) else { return nil }

        // Select candidate files based on function
        let candidates: [CompletionItem]
        if funcName == "image" || funcName == "figure" {
            candidates = imageFiles.map {
                CompletionItem(label: $0, insertText: $0, kind: .value, detail: "Image")
            }
        } else {
            // For bibliography, csv, json, etc. — no candidates yet (can be extended)
            return nil
        }

        guard !candidates.isEmpty else { return nil }

        let filtered: [CompletionItem]
        if typedPath.isEmpty {
            filtered = candidates
        } else {
            let lowerTyped = typedPath.lowercased()
            filtered = candidates.filter { item in
                let path = item.label.lowercased()
                // Path prefix match: "images/p" matches "images/photo.png"
                if path.hasPrefix(lowerTyped) { return true }
                // No slash typed → also match against filename: "photo" matches "images/photo.png"
                if !lowerTyped.contains("/") {
                    let fileName = (item.label as NSString).lastPathComponent.lowercased()
                    if fileName.contains(lowerTyped) { return true }
                }
                return false
            }
        }

        guard !filtered.isEmpty else { return nil }
        if filtered.count == 1, filtered[0].label == typedPath { return nil }

        return .value(prefix: typedPath, isQuoted: true, items: filtered)
    }

    // MARK: - Parameter Completion

    private func parameterCompletions(for text: String, cursorOffset: Int) -> CompletionContext? {
        // Walk backwards from cursor to determine if we're at a parameter-name position
        // i.e., right after `(` or `,` with optional whitespace, possibly with a partial name typed.
        let utf16 = text.utf16
        guard cursorOffset <= utf16.count else { return nil }
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        // Collect the partial word being typed (letters, digits, hyphens)
        var wordStart = cursorIndex
        while wordStart > utf16.startIndex {
            let prev = utf16.index(before: wordStart)
            let ch = text[prev]
            if ch.isLetter || ch == "-" || ch == "_" || ch.isNumber {
                wordStart = prev
            } else {
                break
            }
        }
        let typedPrefix = String(text[wordStart..<cursorIndex])

        // From wordStart, skip whitespace backwards to find `(` or `,`
        var scan = wordStart
        while scan > utf16.startIndex {
            let prev = utf16.index(before: scan)
            let ch = text[prev]
            if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
                scan = prev
            } else {
                break
            }
        }
        guard scan > utf16.startIndex else { return nil }
        let trigger = text[utf16.index(before: scan)]
        guard trigger == "(" || trigger == "," else { return nil }

        // Check we're not after `:` (typing a value, not a param name)
        // Walk backwards from wordStart skipping whitespace — if we hit `:` before `(` or `,`, bail
        var valCheck = wordStart
        while valCheck > utf16.startIndex {
            let prev = utf16.index(before: valCheck)
            let ch = text[prev]
            if ch == " " || ch == "\t" { valCheck = prev; continue }
            if ch == ":" { return nil } // we're in value position
            break
        }

        // Find the function name: walk backwards from the unmatched `(` to get the identifier
        let funcName = findEnclosingFunctionName(in: text, beforeOffset: cursorOffset)
        guard let funcName, let params = parameterDB[funcName] else { return nil }

        // Collect already-used parameter names in this call
        let usedParams = findUsedParameters(in: text, cursorOffset: cursorOffset)

        let paramItems: [CompletionItem] = params.compactMap { (name, detail) in
            guard !usedParams.contains(name) else { return nil }
            if !typedPrefix.isEmpty, !name.hasPrefix(typedPrefix) { return nil }
            let insertText = hintOnlyParameters[funcName]?.contains(name) == true ? nil : name + ": "
            return CompletionItem(label: name, insertText: insertText, kind: .parameter, detail: detail)
        }

        // Add positional value suggestions (e.g. `center` for align, unit hints for v/h)
        var valueItems: [CompletionItem] = []
        if let positionalValues = positionalValueDB[funcName] {
            for (label, insert, detail) in positionalValues {
                if !typedPrefix.isEmpty, !label.localizedCaseInsensitiveContains(typedPrefix) { continue }
                valueItems.append(CompletionItem(label: label, insertText: insert, kind: .value, detail: detail))
            }
        }

        let allItems = valueItems + paramItems
        guard !allItems.isEmpty else { return nil }
        if allItems.count == 1, allItems[0].label == typedPrefix { return nil }
        return .parameter(prefix: typedPrefix, items: allItems)
    }

    /// Find the function name for the innermost unmatched `(` before cursorOffset.
    private func findEnclosingFunctionName(in text: String, beforeOffset: Int) -> String? {
        let utf16 = text.utf16
        let limit = utf16.index(utf16.startIndex, offsetBy: min(beforeOffset, utf16.count))
        var depth = 0
        var pos = limit

        while pos > utf16.startIndex {
            pos = utf16.index(before: pos)
            let ch = text[pos]
            if ch == ")" { depth += 1 }
            else if ch == "(" {
                if depth == 0 {
                    // Found the unmatched `(`. Now read the identifier before it.
                    var nameEnd = pos
                    // Skip whitespace
                    while nameEnd > utf16.startIndex {
                        let prev = utf16.index(before: nameEnd)
                        if text[prev] == " " || text[prev] == "\t" { nameEnd = prev } else { break }
                    }
                    var nameStart = nameEnd
                    while nameStart > utf16.startIndex {
                        let prev = utf16.index(before: nameStart)
                        let c = text[prev]
                        if c.isLetter || c == "-" || c == "_" || c.isNumber {
                            nameStart = prev
                        } else {
                            break
                        }
                    }
                    guard nameStart < nameEnd else { return nil }
                    let name = String(text[nameStart..<nameEnd])
                    // Strip leading `#` if present (e.g. `#text(`)
                    if name.hasPrefix("#") { return String(name.dropFirst()) }
                    return name
                }
                depth -= 1
            }
        }
        return nil
    }

    /// Collect parameter names already used in the current function call.
    private func findUsedParameters(in text: String, cursorOffset: Int) -> Set<String> {
        let utf16 = text.utf16
        let limit = utf16.index(utf16.startIndex, offsetBy: min(cursorOffset, utf16.count))
        var depth = 0
        var pos = limit
        var openParenPos: String.Index?

        // Find the unmatched `(`
        while pos > utf16.startIndex {
            pos = utf16.index(before: pos)
            let ch = text[pos]
            if ch == ")" { depth += 1 }
            else if ch == "(" {
                if depth == 0 { openParenPos = utf16.index(after: pos); break }
                depth -= 1
            }
        }
        guard let start = openParenPos else { return [] }

        // Scan forward from `(` to cursor, collecting `name:` patterns at depth 0
        var used = Set<String>()
        var scanDepth = 0
        var i = start
        while i < limit {
            let ch = text[i]
            if ch == "(" || ch == "[" { scanDepth += 1 }
            else if ch == ")" || ch == "]" { scanDepth -= 1 }
            else if ch == ":" && scanDepth == 0 {
                // Walk backwards from `:` to get the name
                var nameEnd = i
                // skip whitespace before `:`
                while nameEnd > start {
                    let prev = utf16.index(before: nameEnd)
                    if text[prev] == " " || text[prev] == "\t" { nameEnd = prev } else { break }
                }
                var nameStart = nameEnd
                while nameStart > start {
                    let prev = utf16.index(before: nameStart)
                    let c = text[prev]
                    if c.isLetter || c == "-" || c == "_" || c.isNumber { nameStart = prev } else { break }
                }
                if nameStart < nameEnd {
                    used.insert(String(text[nameStart..<nameEnd]))
                }
            }
            i = utf16.index(after: i)
        }
        return used
    }

    // MARK: - Value Completion

    private func valueCompletions(for text: String, cursorOffset: Int) -> CompletionContext? {
        let utf16 = text.utf16
        guard cursorOffset > 0, cursorOffset <= utf16.count else { return nil }
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        // Try to detect if we're in a value position: after `paramName:` with optional whitespace and quote.
        // Case 1: Inside quotes — `param: "partial`
        // Case 2: Unquoted — `param: partial`

        var isQuoted = false
        var valueStart = cursorIndex
        var scanFrom = cursorIndex

        // Walk backwards to find opening `"` or a delimiter
        var probe = cursorIndex
        while probe > utf16.startIndex {
            let prev = utf16.index(before: probe)
            let ch = text[prev]
            if ch == "\"" {
                isQuoted = true
                valueStart = probe   // first char after the quote
                scanFrom = prev      // the quote itself
                break
            } else if ch == ":" || ch == "(" || ch == "," || ch == ")" || ch == "\n" {
                break
            }
            probe = prev
        }

        if !isQuoted {
            // Collect identifier chars for unquoted value
            valueStart = cursorIndex
            while valueStart > utf16.startIndex {
                let prev = utf16.index(before: valueStart)
                let ch = text[prev]
                if ch.isLetter || ch == "-" || ch == "_" || ch.isNumber {
                    valueStart = prev
                } else {
                    break
                }
            }
            scanFrom = valueStart
        }

        let typedValue = String(text[valueStart..<cursorIndex])

        // From scanFrom, skip whitespace backwards to find `:`
        var colonScan = scanFrom
        while colonScan > utf16.startIndex {
            let prev = utf16.index(before: colonScan)
            let ch = text[prev]
            if ch == " " || ch == "\t" {
                colonScan = prev
            } else {
                break
            }
        }
        guard colonScan > utf16.startIndex else { return nil }
        let charBeforeValue = text[utf16.index(before: colonScan)]
        guard charBeforeValue == ":" else { return nil }

        // Get parameter name before `:`
        let colonPos = utf16.index(before: colonScan)
        var paramEnd = colonPos
        while paramEnd > utf16.startIndex {
            let prev = utf16.index(before: paramEnd)
            if text[prev] == " " || text[prev] == "\t" { paramEnd = prev } else { break }
        }
        var paramStart = paramEnd
        while paramStart > utf16.startIndex {
            let prev = utf16.index(before: paramStart)
            let c = text[prev]
            if c.isLetter || c == "-" || c == "_" || c.isNumber {
                paramStart = prev
            } else {
                break
            }
        }
        guard paramStart < paramEnd else { return nil }
        let paramName = String(text[paramStart..<paramEnd])
        let functionName = findEnclosingFunctionName(in: text, beforeOffset: cursorOffset)

        // Look up value suggestions
        let suggestions = valueSuggestionsForParam(paramName, in: functionName)
        guard !suggestions.isEmpty else { return nil }

        let filtered: [CompletionItem]
        if typedValue.isEmpty {
            filtered = suggestions
        } else {
            filtered = suggestions.filter {
                $0.label.localizedCaseInsensitiveContains(typedValue)
            }
        }
        guard !filtered.isEmpty else { return nil }
        if filtered.count == 1, filtered[0].label.caseInsensitiveCompare(typedValue) == .orderedSame { return nil }

        return .value(prefix: typedValue, isQuoted: isQuoted, items: filtered)
    }

    private func valueSuggestionsForParam(_ paramName: String, in functionName: String?) -> [CompletionItem] {
        switch paramName {
        case "font":
            return fontFamilies.map {
                CompletionItem(label: $0, insertText: $0, kind: .value, detail: "Font family")
            }
        case "weight":
            return weightValues.map { (name, num) in
                CompletionItem(label: name, insertText: nil, kind: .value, detail: num)
            }
        default:
            if let functionName, let values = contextualValueDB[functionName]?[paramName] {
                return values.map { (name, detail) in
                    CompletionItem(label: name, insertText: nil, kind: .value, detail: detail)
                }
            }
            guard let values = staticValueDB[paramName] else { return [] }
            return values.map { (name, detail) in
                CompletionItem(label: name, insertText: nil, kind: .value, detail: detail)
            }
        }
    }

    // MARK: - Reference Completion (@)

    /// Detects `@partial` and suggests labels + bib keys.
    private func referenceCompletions(for text: String, cursorOffset: Int) -> CompletionContext? {
        let utf16 = text.utf16
        guard cursorOffset <= utf16.count else { return nil }
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        // Walk backwards collecting identifier chars (letters, digits, hyphen, underscore, dot, colon)
        var start = cursorIndex
        while start > utf16.startIndex {
            let prev = utf16.index(before: start)
            let ch = text[prev]
            if ch == "@" {
                let query = String(text[start..<cursorIndex])
                let allRefs = allReferenceItems(for: text)
                let filtered = query.isEmpty ? allRefs : allRefs.filter {
                    $0.label.localizedCaseInsensitiveContains(query)
                }
                guard !filtered.isEmpty else { return nil }
                if filtered.count == 1, filtered[0].label == query { return nil }
                let prefix = String(text[prev..<cursorIndex])  // includes `@`
                return .atPrefix(prefix: prefix, items: filtered)
            } else if ch.isLetter || ch == "-" || ch == "_" || ch.isNumber || ch == "." || ch == ":" {
                start = prev
                continue
            } else {
                break
            }
        }
        return nil
    }

    /// Detects `<partial` inside `cite(<partial)` or `ref(<partial)`.
    private func angleBracketCompletions(for text: String, cursorOffset: Int) -> CompletionContext? {
        let utf16 = text.utf16
        guard cursorOffset <= utf16.count else { return nil }
        let cursorIndex = utf16.index(utf16.startIndex, offsetBy: cursorOffset)

        // Walk backwards collecting label chars
        var start = cursorIndex
        while start > utf16.startIndex {
            let prev = utf16.index(before: start)
            let ch = text[prev]
            if ch == "<" {
                let query = String(text[start..<cursorIndex])
                // Determine context: inside cite() → bib keys; inside ref() or unknown → labels
                let funcName = findEnclosingFunctionName(in: text, beforeOffset: cursorOffset)
                let candidates: [CompletionItem]
                if funcName == "cite" {
                    candidates = bibEntries.map {
                        CompletionItem(label: $0.key, insertText: $0.key, kind: .reference, detail: $0.type)
                    }
                } else {
                    candidates = allReferenceItems(for: text)
                }
                let filtered = query.isEmpty ? candidates : candidates.filter {
                    $0.label.localizedCaseInsensitiveContains(query)
                }
                guard !filtered.isEmpty else { return nil }
                if filtered.count == 1, filtered[0].label == query { return nil }
                return .angleBracket(prefix: query, items: filtered)
            } else if ch.isLetter || ch == "-" || ch == "_" || ch.isNumber || ch == "." || ch == ":" {
                start = prev
                continue
            } else {
                break
            }
        }
        return nil
    }

    /// Builds the full list of reference items: labels from current text + external labels + bib keys.
    private func allReferenceItems(for text: String) -> [CompletionItem] {
        var items: [CompletionItem] = []

        // Labels from current text
        for (name, kind) in scanLabels(in: text) {
            items.append(CompletionItem(label: name, insertText: name, kind: .reference, detail: kind))
        }

        // Labels from other project files
        for (name, kind) in externalLabels {
            items.append(CompletionItem(label: name, insertText: name, kind: .reference, detail: kind))
        }

        // BibTeX keys
        for entry in bibEntries {
            items.append(CompletionItem(label: entry.key, insertText: entry.key, kind: .reference, detail: entry.type))
        }

        return items
    }

    // MARK: - Label Scanning

    /// Scans text for `<label-name>` definitions and infers their kind from context.
    func scanLabels(in text: String) -> [(name: String, kind: String)] {
        // Pattern: `<identifier>` where identifier is [a-zA-Z0-9_\-.:]+
        // Must not be preceded by another `<` (to skip `<<`) or inside code.
        guard let regex = try? NSRegularExpression(pattern: #"(?<![<\\])<([a-zA-Z][a-zA-Z0-9_\-.:]*?)>"#) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var results: [(String, String)] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            let name = nsText.substring(with: nameRange)

            // Infer kind by looking at context before the label
            let kind = inferLabelKind(in: nsText, beforeLocation: match.range.location)
            results.append((name, kind))
        }
        return results
    }

    private func inferLabelKind(in text: NSString, beforeLocation loc: Int) -> String {
        // Look at up to 200 chars before the label for context clues
        let searchStart = max(0, loc - 200)
        let searchLen = loc - searchStart
        guard searchLen > 0 else { return "label" }
        let context = text.substring(with: NSRange(location: searchStart, length: searchLen))
        let lower = context.lowercased()

        // Check from most specific to least
        if lower.contains("#figure") || lower.contains("figure(") { return "figure" }
        if lower.contains("#table") || lower.contains("table(") { return "table" }
        if lower.contains("#equation") || lower.hasSuffix("$") || lower.contains("$ ") { return "equation" }
        // Headings: lines starting with `=`
        if let lastNewline = context.lastIndex(of: "\n") {
            let lineStart = context[context.index(after: lastNewline)...]
            let trimmed = lineStart.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=") { return "heading" }
        } else {
            let trimmed = context.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=") { return "heading" }
        }
        return "label"
    }

    // MARK: - BibTeX Parsing

    /// Parses BibTeX content and extracts (key, entryType) pairs.
    static func parseBibTeX(_ content: String) -> [(key: String, type: String)] {
        // Match @type{key, patterns
        guard let regex = try? NSRegularExpression(pattern: #"@(\w+)\s*\{\s*([^,\s]+)"#) else {
            return []
        }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let typeRange = match.range(at: 1)
            let keyRange = match.range(at: 2)
            guard typeRange.location != NSNotFound, keyRange.location != NSNotFound else { return nil }
            let type = nsContent.substring(with: typeRange).lowercased()
            let key = nsContent.substring(with: keyRange)
            // Skip @comment, @string, @preamble
            guard type != "comment", type != "string", type != "preamble" else { return nil }
            return (key: key, type: type)
        }
    }
}
