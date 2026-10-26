import ContrastCore
import Testing

// Shared fixtures. Every name and value here is invented; the two themes are
// the examples from DESIGN.md 8.1 and 8.2.

enum Hello {
    static let theme = Theme("Hello",
        pairs: [ColorPair("text", on: "surface", role: .bodyText),
                ColorPair("hint", on: "surface", role: .bodyText)],
        variants: [Variant("light", hex: ["text": "#1E2B37", "hint": "#8B959F", "surface": "#FFFFFF"])])
}

enum Harbor {
    static let pairs = [
        ColorPair("text", on: "surface", role: .bodyText),
        ColorPair("subtitle", on: "card", role: .bodyText),
        ColorPair("link", on: "surface", role: .bodyText),
        ColorPair("icon-outline", on: "surface", role: .uiComponent),
        ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper"),
        ColorPair("logo-text", on: "badge", role: .largeText, note: "Wordmark"),
    ]

    static let theme = Theme("Harbor", pairs: pairs, variants: [
        Variant("light", hex: [
            "text": "#1E2B37", "subtitle": "#5A6B7C", "surface": "#FFFFFF",
            "card": "#F1F3F6", "link": "#1D6BAE", "icon-outline": "#A1ACB7",
            "glass": "#FFFFFFB3", "wallpaper": "#476CA3", "caption": "#2A3B4D",
            "badge": "#C9561A", "logo-text": "#FFFFFF",
        ]),
        Variant("dark", hex: [
            "text": "#E9EEF1", "subtitle": "#697887", "surface": "#111921",
            "card": "#1D2934", "link": "#69B1EC", "icon-outline": "#54616D",
            "glass": "#11192199", "wallpaper": "#476CA3", "caption": "#D3D9DE",
            "badge": "#E37D27", "logo-text": "#FFFFFF",
        ]),
        Variant("increased-contrast", hex: [
            "text": "#000000", "subtitle": "#292E33", "surface": "#FFFFFF",
            "card": "#F6F6F6", "link": "#0A4D89", "icon-outline": "#4B535E",
            "glass": "#FFFFFFE6", "wallpaper": "#476CA3", "caption": "#000000",
            "badge": "#9E3F06", "logo-text": "#FFFFFF",
        ]),
    ])

    static let waivers = [
        Waiver("logo-text", on: "badge", variant: nil,
               reason: "Logotype, exempt under 1.4.3",
               expiryNote: "Revisit if the wordmark changes"),
    ]

    static let baselineJSON = """
        {
          "entries" : [
            {
              "background" : "surface",
              "foreground" : "icon-outline",
              "ratio" : 2.7916390550241523,
              "variant" : "dark"
            }
          ],
          "level" : "AA",
          "schemaVersion" : 1
        }
        """
}

/// Parses a hex literal in tests; a typo fails the test at the `try`.
func hex(_ text: String) throws -> SRGBColor {
    try SRGBColor(hex: text)
}

/// The error a closure throws, or nil. Used instead of the newer
/// `#expect(throws:)` overloads that return the error, so the tests also
/// build with the Swift 6.0 toolchain the package declares.
func thrownError(_ body: () throws -> Void) -> Error? {
    do {
        try body()
        return nil
    } catch {
        return error
    }
}

/// A one-variant theme from (name, hex) entries, for focused audit tests.
func singleVariantTheme(_ name: String = "T", variant: String = "v", pairs: [ColorPair],
                        colors: [(String, String)]) throws -> Theme {
    let entries = try colors.map { (name: $0.0, color: try SRGBColor(hex: $0.1)) }
    return Theme(name, pairs: pairs, variants: [Variant(variant, entries: entries)])
}

/// Baseline JSON with one entry per tuple, for building recorded ratios
/// exactly as a file on disk would.
func baselineJSON(level: String = "AA", version: Int = 1,
                  _ entries: [(variant: String, foreground: String, background: String, ratio: Double)]) -> String {
    let items = entries.map { entry in
        "{\"variant\": \"\(entry.variant)\", \"foreground\": \"\(entry.foreground)\", "
            + "\"background\": \"\(entry.background)\", \"ratio\": \(entry.ratio)}"
    }
    return "{\"schemaVersion\": \(version), \"level\": \"\(level)\", \"entries\": [\(items.joined(separator: ", "))]}"
}

/// Splits text into the text around its numbers (each number replaced by
/// `#`) and the numbers' values. A number starts with a digit, or with `-`
/// followed by a digit, that does not continue a word.
func textAndNumbers(_ text: String) -> (text: String, numbers: [Double]) {
    let chars = Array(text)
    var shape = ""
    var numbers: [Double] = []
    var i = 0
    func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    while i < chars.count {
        let c = chars[i]
        let startsNumber = isDigit(c) || (c == "-" && i + 1 < chars.count && isDigit(chars[i + 1]))
        let continuesWord = i > 0 && (chars[i - 1].isLetter || isDigit(chars[i - 1]) || chars[i - 1] == "_")
        guard startsNumber, !continuesWord else {
            shape.append(c)
            i += 1
            continue
        }
        var j = i + 1
        while j < chars.count, isDigit(chars[j]) || ".eE+-".contains(chars[j]) {
            j += 1
        }
        let token = String(chars[i..<j])
        guard let value = Double(token) else {
            shape += token
            i = j
            continue
        }
        shape.append("#")
        numbers.append(value)
        i = j
    }
    return (shape, numbers)
}

/// Compares JSON output with an expected literal: all text exactly, numbers
/// to a relative 1e-12. The ratios come from `pow`, whose last bit may differ
/// between Apple's libm and glibc, so a byte-for-byte comparison could fail on
/// Linux for reasons that have nothing to do with this package.
func expectJSON(_ actual: String, _ expected: String,
                sourceLocation: SourceLocation = #_sourceLocation) {
    let lhs = textAndNumbers(actual)
    let rhs = textAndNumbers(expected)
    #expect(lhs.text == rhs.text, sourceLocation: sourceLocation)
    #expect(lhs.numbers.count == rhs.numbers.count, sourceLocation: sourceLocation)
    for (a, b) in zip(lhs.numbers, rhs.numbers) where abs(a - b) > 1e-12 * max(abs(a), abs(b)) {
        Issue.record("number \(a) differs from expected \(b)", sourceLocation: sourceLocation)
    }
}
