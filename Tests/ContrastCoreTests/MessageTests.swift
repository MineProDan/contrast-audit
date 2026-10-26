import ContrastCore
import Testing

// Exact-string tests for the failure message format in DESIGN.md 6.1. Note
// the two spaces between the pair, the ratio and "needs".

@Suite("Failure messages")
struct MessageTests {
    @Test("Hello theme (DESIGN.md 8.1)")
    func hello() throws {
        let report = Hello.theme.audit(level: .aa)
        #expect(!report.passed)
        #expect(try #require(report.failureDescription) == """
            Contrast audit failed for theme 'Hello' at AA: 1 of 2 checks failed (2 pairs x 1 variant).
              [light] 'hint' on 'surface'  3.04:1  needs 4.50:1 (AA, body text)
            """)
        #expect(report.summary == "Hello at AA: 1 passed, 1 failed, 0 waived, 0 known failures, 0 regressed, 0 invalid.")
    }

    @Test("Harbor theme with its waiver and baseline (DESIGN.md 6.1 and 8.2)")
    func harbor() throws {
        let baseline = try Baseline(json: Harbor.baselineJSON)
        let report = Harbor.theme.audit(level: .aa, waivers: Harbor.waivers, baseline: baseline)
        #expect(!report.passed)
        #expect(try #require(report.failureDescription) == """
            Contrast audit failed for theme 'Harbor' at AA: 2 of 18 checks failed (6 pairs x 3 variants).
              [light] 'icon-outline' on 'surface'  2.30:1  needs 3.00:1 (AA, UI component)
              [dark] 'subtitle' on 'card'  3.26:1  needs 4.50:1 (AA, body text)
            Not counted as failures: 1 waived, 1 known failure (baseline).
            """)
        #expect(report.summary
            == "Harbor at AA: 14 passed, 2 failed, 1 waived, 1 known failure, 0 regressed, 0 invalid.")
        #expect(report.unusedWaivers.isEmpty)
        #expect(report.outdatedBaselineEntries.isEmpty)
    }

    @Test("Regression line prints the baseline and the drop to six decimals")
    func regression() throws {
        let theme = try singleVariantTheme("Harbor", variant: "dark",
                                           pairs: [ColorPair("icon-outline", on: "surface", role: .uiComponent)],
                                           colors: [("icon-outline", "#4D5964"), ("surface", "#111921")])
        let report = theme.audit(level: .aa, baseline: try Baseline(json: Harbor.baselineJSON))
        #expect(try #require(report.failureDescription) == """
            Contrast audit failed for theme 'Harbor' at AA: 1 of 1 check failed (1 pair x 1 variant).
              [dark] 'icon-outline' on 'surface'  2.47:1  needs 3.00:1 (AA, UI component), regressed from baseline 2.79:1 (-0.319989)
            """)
        #expect(report.summary == "Harbor at AA: 0 passed, 0 failed, 0 waived, 0 known failures, 1 regressed, 0 invalid.")
    }

    @Test("Unreachable hint when neither black nor white meets the requirement")
    func unreachable() throws {
        let theme = try singleVariantTheme("Chips", variant: "light",
                                           pairs: [ColorPair("label", on: "chip", role: .bodyText)],
                                           colors: [("label", "#FFFFFF"), ("chip", "#6D7E81")])
        #expect(try #require(theme.audit(level: .aaa).failureDescription) == """
            Contrast audit failed for theme 'Chips' at AAA: 1 of 1 check failed (1 pair x 1 variant).
              [light] 'label' on 'chip'  4.24:1  needs 7.00:1 (AAA, body text); unreachable on this background, best possible 4.95:1
            """)
        // At AA the same pair still fails, but black would pass, so no hint.
        #expect(try #require(theme.audit(level: .aa).failureDescription).hasSuffix("needs 4.50:1 (AA, body text)"))
    }

    @Test("Missing color and missing backdrop lines")
    func invalidLines() throws {
        let theme = try singleVariantTheme("Harbor", variant: "dark",
                                           pairs: [ColorPair("link", on: "banner", role: .bodyText),
                                                   ColorPair("caption", on: "glass", role: .bodyText)],
                                           colors: [("link", "#69B1EC"), ("caption", "#D3D9DE"),
                                                    ("glass", "#11192199")])
        let report = theme.audit(level: .aa)
        #expect(try #require(report.failureDescription) == """
            Contrast audit failed for theme 'Harbor' at AA: 2 of 2 checks failed (2 pairs x 1 variant).
              [dark] 'link' on 'banner'  invalid: no color named 'banner' in this variant
              [dark] 'caption' on 'glass'  invalid: background 'glass' is translucent (alpha 0.60) and the pair has no backdrop
            """)
        #expect(report.summary == "Harbor at AA: 0 passed, 0 failed, 0 waived, 0 known failures, 0 regressed, 2 invalid.")
    }

    @Test("Level mismatch is a theme problem listed first")
    func levelMismatch() throws {
        let baseline = try Baseline(json: baselineJSON(level: "AAA", []))
        let report = Hello.theme.audit(level: .aa, baseline: baseline)
        #expect(try #require(report.failureDescription) == """
            Contrast audit failed for theme 'Hello' at AA: 1 theme problem; 1 of 2 checks failed (2 pairs x 1 variant).
              [theme] baseline was recorded at AAA but this audit runs at AA
              [light] 'hint' on 'surface'  3.04:1  needs 4.50:1 (AA, body text)
            """)
    }

    @Test("Footer lines use singular and plural forms")
    func footers() throws {
        let pairs = [ColorPair("a", on: "bg", role: .bodyText), ColorPair("b", on: "bg", role: .bodyText),
                     ColorPair("c", on: "bg", role: .bodyText), ColorPair("d", on: "bg", role: .bodyText)]
        let theme = try singleVariantTheme(pairs: pairs, colors: [("a", "#777777"), ("b", "#777777"),
                                                                  ("c", "#777777"), ("d", "#777777"),
                                                                  ("bg", "#FFFFFF")])
        let ratio = try ContrastRatio(foreground: hex("#777777"), background: hex("#FFFFFF")).value

        // One of each: a and b waived/known, c failing; one unused waiver and
        // one outdated entry (for a pair that does not exist).
        let single = theme.audit(level: .aa,
                                 waivers: [Waiver("a", on: "bg", variant: nil, reason: "r"),
                                           Waiver("x", on: "bg", variant: nil, reason: "r")],
                                 baseline: try Baseline(json: baselineJSON([("v", "b", "bg", ratio),
                                                                            ("v", "gone", "bg", 2)])))
        #expect(try #require(single.failureDescription) == """
            Contrast audit failed for theme 'T' at AA: 2 of 4 checks failed (4 pairs x 1 variant).
              [v] 'c' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
              [v] 'd' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
            Not counted as failures: 1 waived, 1 known failure (baseline).
            Housekeeping: 1 unused waiver, 1 outdated baseline entry.
            """)

        let plural = theme.audit(level: .aa,
                                 waivers: [Waiver("x", on: "bg", variant: nil, reason: "r"),
                                           Waiver("y", on: "bg", variant: nil, reason: "r")],
                                 baseline: try Baseline(json: baselineJSON([("v", "a", "bg", ratio),
                                                                            ("v", "b", "bg", ratio),
                                                                            ("v", "gone", "bg", 2),
                                                                            ("w", "a", "bg", 2)])))
        #expect(try #require(plural.failureDescription) == """
            Contrast audit failed for theme 'T' at AA: 2 of 4 checks failed (4 pairs x 1 variant).
              [v] 'c' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
              [v] 'd' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
            Not counted as failures: 2 known failures (baseline).
            Housekeeping: 2 unused waivers, 2 outdated baseline entries.
            """)

        // Only non-zero counts are named: no baseline, so none is mentioned.
        let waivedOnly = theme.audit(level: .aa, waivers: [Waiver("a", on: "bg", variant: nil, reason: "r")])
        #expect(try #require(waivedOnly.failureDescription) == """
            Contrast audit failed for theme 'T' at AA: 3 of 4 checks failed (4 pairs x 1 variant).
              [v] 'b' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
              [v] 'c' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
              [v] 'd' on 'bg'  4.47:1  needs 4.50:1 (AA, body text)
            Not counted as failures: 1 waived.
            """)
    }

    @Test("Problem and error descriptions")
    func descriptions() {
        let problems: [(AuditProblem, String)] = [
            (.noPairs, "theme declares no pairs, so nothing was checked"),
            (.noVariants, "theme declares no variants, so nothing was checked"),
            (.duplicateVariant("dark"), "variant 'dark' is declared more than once; only the first is audited"),
            (.duplicatePair(foreground: "a", background: "b"),
             "pair 'a' on 'b' is declared more than once; only the first is checked"),
            (.duplicateColorName(variant: "dark", name: "a"),
             "variant 'dark' defines color 'a' more than once; checks that use it are invalid"),
            (.malformedColor(variant: "dark", name: "a", input: "#12"),
             "variant 'dark' color 'a' has malformed hex '#12'; expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA"),
            (.unusableColor("a"), "color 'a' is malformed or defined more than once in this variant"),
            (.unknownBackdrop("wall"), "no backdrop color named 'wall' in this variant"),
            (.translucentBackdrop("wall", alpha: 0.5), "backdrop 'wall' is translucent (alpha 0.50); a backdrop must be opaque"),
        ]
        for (problem, text) in problems {
            #expect(problem.description == text)
        }
        #expect(ContrastError.missingBackdrop.description == "the background is translucent and no backdrop was given")
        #expect(ContrastError.unsupportedBaselineVersion(2).description
            == "unsupported baseline schemaVersion 2; this version reads schemaVersion 1")
        #expect(ContrastError.malformedBaseline("x").description == "malformed baseline: x")
        #expect(ContrastError.componentOutOfRange(component: "red", value: 1.5).description
            == "red component is 1.5; components must be finite and within 0...1")
        #expect(ContrastError.unconvertibleColor("pattern").description
            == "cannot convert the color to sRGB: pattern")
    }
}
