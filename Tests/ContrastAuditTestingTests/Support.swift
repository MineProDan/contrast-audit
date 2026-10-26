import ContrastCore
import Foundation

// Shared fixtures. Every name and value here is invented. Hello and Harbor
// are the examples from DESIGN.md 8.1 and 8.2 (the same declarations as in
// ContrastCoreTests/Support.swift; test targets cannot share source files).

enum Fixtures {
    /// Fails one body-text check (DESIGN.md 8.1).
    static let hello = Theme("Hello",
        pairs: [ColorPair("text", on: "surface", role: .bodyText),
                ColorPair("hint", on: "surface", role: .bodyText)],
        variants: [Variant("light", hex: ["text": "#1E2B37", "hint": "#8B959F", "surface": "#FFFFFF"])])

    static let helloMessage = """
        Contrast audit failed for theme 'Hello' at AA: 1 of 2 checks failed (2 pairs x 1 variant).
          [light] 'hint' on 'surface'  3.04:1  needs 4.50:1 (AA, body text)
        """

    /// Passes at AA in both variants.
    static let calm = Theme("Calm",
        pairs: [ColorPair("text", on: "surface", role: .bodyText),
                ColorPair("hint", on: "surface", role: .bodyText),
                ColorPair("border", on: "surface", role: .uiComponent)],
        variants: [
            Variant("light", hex: ["text": "#1E2B37", "hint": "#5A6B7C", "border": "#7D8894", "surface": "#FFFFFF"]),
            Variant("dark", hex: ["text": "#E9EEF1", "hint": "#9AA6B2", "border": "#6A7885", "surface": "#111921"]),
        ])

    static let harborPairs = [
        ColorPair("text", on: "surface", role: .bodyText),
        ColorPair("subtitle", on: "card", role: .bodyText),
        ColorPair("link", on: "surface", role: .bodyText),
        ColorPair("icon-outline", on: "surface", role: .uiComponent),
        ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper"),
        ColorPair("logo-text", on: "badge", role: .largeText, note: "Wordmark"),
    ]

    static let harbor = Theme("Harbor", pairs: harborPairs, variants: [
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

    static let harborWaivers = [
        Waiver("logo-text", on: "badge", variant: nil,
               reason: "Logotype, exempt under 1.4.3",
               expiryNote: "Revisit if the wordmark changes"),
    ]

    static func harborBaseline() throws -> Baseline {
        try Baseline(json: """
            {"schemaVersion": 1, "level": "AA", "entries": [{"variant": "dark", "foreground": "icon-outline",
             "background": "surface", "ratio": 2.7916390550241523}]}
            """)
    }

    /// The message from DESIGN.md 6.1, with the waiver and baseline applied.
    static let harborMessage = """
        Contrast audit failed for theme 'Harbor' at AA: 2 of 18 checks failed (6 pairs x 3 variants).
          [light] 'icon-outline' on 'surface'  2.30:1  needs 3.00:1 (AA, UI component)
          [dark] 'subtitle' on 'card'  3.26:1  needs 4.50:1 (AA, body text)
        Not counted as failures: 1 waived, 1 known failure (baseline).
        """
}

/// Where an issue was recorded: file name and line.
struct RecordedLocation: Equatable, CustomStringConvertible {
    let file: String
    let line: Int

    var description: String { "\(file):\(line)" }

    init(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    /// The location of a call on `line` of the file at `filePath`.
    init(filePath: String, line: Int) {
        self.init(file: URL(fileURLWithPath: filePath).lastPathComponent, line: line)
    }
}

/// Collects the locations of matched issues. The framework matchers are
/// `@Sendable` closures, so they cannot append to a captured local array;
/// the lock makes the box safe to share with them.
final class LocationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [RecordedLocation] = []

    func append(_ location: RecordedLocation) {
        lock.lock()
        locations.append(location)
        lock.unlock()
    }

    var all: [RecordedLocation] {
        lock.lock()
        defer { lock.unlock() }
        return locations
    }
}
