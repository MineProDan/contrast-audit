import ContrastCore
import Testing

@Suite("Audit")
struct AuditTests {
    @Test("Results follow variant order, then pair order")
    func declarationOrder() {
        let report = Harbor.theme.audit(level: .aa)
        let order = report.results.map { "\($0.variant)/\($0.pair.foreground)/\($0.pair.background)" }
        var expected: [String] = []
        for variant in ["light", "dark", "increased-contrast"] {
            for pair in Harbor.pairs {
                expected.append("\(variant)/\(pair.foreground)/\(pair.background)")
            }
        }
        #expect(order == expected)
        #expect(report.themeName == "Harbor")
        #expect(report.level == .aa)
    }

    @Test("Each result carries the requirement for its role and the measured ratio")
    func resultFields() throws {
        let report = Hello.theme.audit(level: .aaa)
        #expect(report.results.count == 2)
        let text = try #require(report.results.first)
        #expect(text.required.value == 7)
        #expect(text.status == .passed)
        #expect(text.ratio?.description == "14.42:1")
        let hint = report.results[1]
        #expect(hint.status == .failed)
        #expect(hint.ratio?.description == "3.04:1")
    }

    @Test("A passing theme passes with no failure description")
    func passingTheme() throws {
        let theme = try singleVariantTheme(pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                                           colors: [("ink", "#000000"), ("paper", "#FFFFFF")])
        let report = theme.audit(level: .aaa)
        #expect(report.passed)
        #expect(report.failureDescription == nil)
        #expect(report.summary == "T at AAA: 1 passed, 0 failed, 0 waived, 0 known failures, 0 regressed, 0 invalid.")
    }

    @Test("A missing color makes the check invalid, not skipped")
    func missingColor() throws {
        let theme = try singleVariantTheme(pairs: [ColorPair("link", on: "banner", role: .bodyText),
                                                   ColorPair("ink", on: "paper", role: .bodyText)],
                                           colors: [("link", "#0000FF"), ("ink", "#000000"), ("paper", "#FFFFFF")])
        let report = theme.audit(level: .aa)
        #expect(report.results.count == 2)
        #expect(report.results[0].status == .invalid(.missingColor("banner")))
        #expect(report.results[0].ratio == nil)
        #expect(report.results[1].status == .passed)
        #expect(!report.passed)
    }

    @Test("A duplicate pair is a theme problem and the first declaration is used")
    func duplicatePair() throws {
        let theme = try singleVariantTheme(
            pairs: [ColorPair("ink", on: "paper", role: .largeText),
                    ColorPair("ink", on: "paper", role: .bodyText),
                    ColorPair("ink", on: "paper", role: .uiComponent)],
            colors: [("ink", "#777777"), ("paper", "#FFFFFF")])
        let report = theme.audit(level: .aa)
        #expect(report.problems == [.duplicatePair(foreground: "ink", background: "paper")])
        #expect(report.results.count == 1)
        #expect(report.results[0].pair.role == .largeText)
        #expect(report.results[0].status == .passed)
        #expect(!report.passed)
    }

    @Test("A duplicate color name is a theme problem and makes the color unusable")
    func duplicateColor() {
        let theme = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText),
                                       ColorPair("paper", on: "ink", role: .bodyText)],
                          variants: [Variant("v", hex: ["ink": "#000000", "paper": "#FFFFFF", "ink": "#111111"])])
        let report = theme.audit(level: .aa)
        #expect(report.problems == [.duplicateColorName(variant: "v", name: "ink")])
        #expect(report.results.map(\.status) == [.invalid(.unusableColor("ink")), .invalid(.unusableColor("ink"))])
    }

    @Test("A malformed duplicate is reported once, as a duplicate")
    func malformedDuplicateColor() {
        let theme = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                          variants: [Variant("v", hex: ["ink": "#000000", "paper": "#FFFFFF", "ink": "#XYZ"])])
        let report = theme.audit(level: .aa)
        #expect(report.problems == [.duplicateColorName(variant: "v", name: "ink")])
        #expect(report.results.map(\.status) == [.invalid(.unusableColor("ink"))])
    }

    @Test("A duplicate variant is a theme problem and only the first is audited")
    func duplicateVariant() {
        let theme = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                          variants: [Variant("v", hex: ["ink": "#000000", "paper": "#FFFFFF"]),
                                     Variant("v", hex: ["ink": "#FFFFFF", "paper": "#FFFFFF"]),
                                     Variant("v", hex: ["ink": "#FFFFFF", "paper": "#FFFFFF"])])
        let report = theme.audit(level: .aa)
        #expect(report.problems == [.duplicateVariant("v")])
        #expect(report.results.count == 1)
        #expect(report.results[0].status == .passed)
    }

    @Test("An empty theme fails")
    func emptyTheme() {
        let noPairs = Theme("T", pairs: [], variants: [Variant("v", hex: ["ink": "#000000"])]).audit(level: .aa)
        #expect(noPairs.problems == [.noPairs])
        #expect(noPairs.results.isEmpty)
        #expect(!noPairs.passed)

        let noVariants = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText)], variants: [])
            .audit(level: .aa)
        #expect(noVariants.problems == [.noVariants])
        #expect(!noVariants.passed)

        let nothing = Theme("Empty", pairs: [], variants: []).audit(level: .aa)
        #expect(nothing.problems == [.noPairs, .noVariants])
        #expect(nothing.failureDescription == """
            Contrast audit failed for theme 'Empty' at AA: 2 theme problems; 0 of 0 checks failed (0 pairs x 0 variants).
              [theme] theme declares no pairs, so nothing was checked
              [theme] theme declares no variants, so nothing was checked
            """)
        #expect(nothing.summary
            == "Empty at AA: 0 passed, 0 failed, 0 waived, 0 known failures, 0 regressed, 0 invalid, 2 theme problems.")
    }

    @Test("Malformed palette hex is a theme problem and the checks using it are invalid")
    func malformedPaletteHex() {
        let theme = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText),
                                       ColorPair("ink", on: "card", role: .bodyText)],
                          variants: [Variant("v", hex: ["ink": "#000000", "paper": "#FFFFF", "card": "#FFFFFF",
                                                        "unused": "nope"])])
        let report = theme.audit(level: .aa)
        #expect(report.problems == [.malformedColor(variant: "v", name: "paper", input: "#FFFFF"),
                                    .malformedColor(variant: "v", name: "unused", input: "nope")])
        #expect(report.results.map(\.status) == [.invalid(.unusableColor("paper")), .passed])
        #expect(!report.passed)
    }

    @Test("All three variant initializers produce the same audit")
    func variantInitializers() throws {
        let pairs = [ColorPair("ink", on: "paper", role: .bodyText)]
        let ink = try hex("#5A6B7C")
        let paper = try hex("#F1F3F6")
        let themes = [
            Theme("T", pairs: pairs, variants: [Variant("v", hex: ["ink": "#5A6B7C", "paper": "#F1F3F6"])]),
            Theme("T", pairs: pairs, variants: [Variant("v", colors: ["ink": ink, "paper": paper])]),
            Theme("T", pairs: pairs, variants: [Variant("v", entries: [(name: "ink", color: ink),
                                                                       (name: "paper", color: paper)])]),
        ]
        let results = themes.map { $0.audit(level: .aa).results }
        #expect(results[0] == results[1])
        #expect(results[1] == results[2])
    }
}

@Suite("Audit with transparency")
struct AuditAlphaTests {
    static let pairs = [ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper")]

    @Test("A translucent background is resolved over the variant's own backdrop")
    func backdropPerVariant() throws {
        let report = Harbor.theme.audit(level: .aa)
        let caption = try #require(report.results.first { $0.variant == "light" && $0.pair.foreground == "caption" })
        #expect(caption.status == .passed)
        #expect(caption.ratio?.description == "7.59:1")
        let expected = try ContrastRatio(foreground: hex("#2A3B4D"), background: hex("#FFFFFFB3"),
                                         backdrop: hex("#476CA3"))
        #expect(caption.ratio == expected)
    }

    @Test("A translucent background without a backdrop is invalid")
    func missingBackdrop() throws {
        let theme = try singleVariantTheme(pairs: [ColorPair("caption", on: "glass", role: .bodyText)],
                                           colors: [("caption", "#D3D9DE"), ("glass", "#11192199")])
        let status = theme.audit(level: .aa).results.first?.status
        #expect(status == .invalid(.missingBackdrop(background: "glass", alpha: 0x99 / 255.0)))
    }

    @Test("A backdrop name missing from the palette is invalid")
    func unknownBackdrop() throws {
        let theme = try singleVariantTheme(pairs: Self.pairs,
                                           colors: [("caption", "#D3D9DE"), ("glass", "#11192199")])
        #expect(theme.audit(level: .aa).results.first?.status == .invalid(.unknownBackdrop("wallpaper")))
    }

    @Test("A translucent backdrop is invalid")
    func translucentBackdrop() throws {
        let theme = try singleVariantTheme(pairs: Self.pairs,
                                           colors: [("caption", "#D3D9DE"), ("glass", "#11192199"),
                                                    ("wallpaper", "#476CA380")])
        #expect(theme.audit(level: .aa).results.first?.status
            == .invalid(.translucentBackdrop("wallpaper", alpha: 0x80 / 255.0)))
    }

    @Test("A malformed backdrop is unusable")
    func malformedBackdrop() {
        let theme = Theme("T", pairs: Self.pairs, variants: [
            Variant("v", hex: ["caption": "#D3D9DE", "glass": "#11192199", "wallpaper": "#47"]),
        ])
        #expect(theme.audit(level: .aa).results.first?.status == .invalid(.unusableColor("wallpaper")))
    }

    @Test("The backdrop is not looked up where the background is opaque")
    func backdropIgnoredWhenOpaque() throws {
        // No "wallpaper" in this palette, and that is fine: "glass" is opaque here.
        let theme = try singleVariantTheme(pairs: Self.pairs,
                                           colors: [("caption", "#000000"), ("glass", "#FFFFFF")])
        let result = try #require(theme.audit(level: .aa).results.first)
        #expect(result.status == .passed)
        #expect(result.ratio?.value == 21)
    }

    @Test("A translucent foreground is composited over the resolved background")
    func translucentForeground() throws {
        let theme = try singleVariantTheme(pairs: Self.pairs,
                                           colors: [("caption", "#2A3B4D99"), ("glass", "#FFFFFFB3"),
                                                    ("wallpaper", "#476CA3")])
        let result = try #require(theme.audit(level: .aa).results.first)
        let expected = try ContrastRatio(foreground: hex("#2A3B4D99"), background: hex("#FFFFFFB3"),
                                         backdrop: hex("#476CA3"))
        #expect(result.ratio == expected)
    }
}

@Suite("Waivers")
struct WaiverTests {
    static let theme = Theme("W", pairs: [ColorPair("logo", on: "badge", role: .largeText),
                                          ColorPair("ink", on: "paper", role: .bodyText)],
                             variants: [Variant("light", hex: ["logo": "#FFFFFF", "badge": "#E37D27",
                                                               "ink": "#000000", "paper": "#FFFFFF"]),
                                        Variant("dark", hex: ["logo": "#FFFFFF", "badge": "#E37D27",
                                                              "ink": "#FFFFFF", "paper": "#000000"])])

    @Test("A waiver for every variant waives each failing check")
    func allVariants() {
        let waiver = Waiver("logo", on: "badge", variant: nil, reason: "Logotype")
        let report = Self.theme.audit(level: .aa, waivers: [waiver])
        #expect(report.results.map(\.status) == [.waived(waiver), .passed, .waived(waiver), .passed])
        #expect(report.passed)
        #expect(report.unusedWaivers.isEmpty)
        #expect(report.summary == "W at AA: 2 passed, 0 failed, 2 waived, 0 known failures, 0 regressed, 0 invalid.")
    }

    @Test("A per-variant waiver leaves the other variant failing")
    func perVariant() {
        let waiver = Waiver("logo", on: "badge", variant: "dark", reason: "Logotype", expiryNote: "2.0")
        let report = Self.theme.audit(level: .aa, waivers: [waiver])
        #expect(report.results.map(\.status) == [.failed, .passed, .waived(waiver), .passed])
        #expect(!report.passed)
    }

    @Test("Waived checks keep their ratio and are never counted as passed")
    func notAPass() {
        let waiver = Waiver("logo", on: "badge", variant: nil, reason: "Logotype")
        let report = Self.theme.audit(level: .aa, waivers: [waiver])
        let waived = report.results[0]
        #expect(waived.ratio?.description == "2.90:1")
        #expect(waived.status != .passed)
        #expect(report.results.filter { $0.status == .passed }.count == 2)
    }

    @Test("A waiver that matches nothing, or only a passing check, is unused and does not fail")
    func unused() {
        let typo = Waiver("logo", on: "bagde", variant: nil, reason: "Typo")
        let passing = Waiver("ink", on: "paper", variant: "light", reason: "Not needed")
        let real = Waiver("logo", on: "badge", variant: nil, reason: "Logotype")
        let duplicate = Waiver("logo", on: "badge", variant: "dark", reason: "Second match")
        let report = Self.theme.audit(level: .aa, waivers: [typo, passing, real, duplicate])
        #expect(report.unusedWaivers == [typo, passing, duplicate])
        #expect(report.results[2].status == .waived(real))
        #expect(report.passed)
        #expect(report.failureDescription == nil)
    }

    @Test("A waiver never applies to an invalid check")
    func neverHidesInvalid() {
        let theme = Theme("W", pairs: [ColorPair("logo", on: "badge", role: .largeText)],
                          variants: [Variant("v", hex: ["logo": "#FFFFFF"])])
        let waiver = Waiver("logo", on: "badge", variant: nil, reason: "Logotype")
        let report = theme.audit(level: .aa, waivers: [waiver])
        #expect(report.results.first?.status == .invalid(.missingColor("badge")))
        #expect(report.unusedWaivers == [waiver])
        #expect(!report.passed)
    }
}
