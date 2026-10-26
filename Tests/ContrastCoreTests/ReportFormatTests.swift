import ContrastCore
import Foundation
import Testing

// Exact-string tests for AuditReport.markdown() and json() (DESIGN.md 6.3 and
// 6.4). They run on every platform, including Linux. Markdown is compared
// byte for byte; JSON through expectJSON, which compares all text exactly and
// numbers to a relative 1e-12, because unrounded ratios may differ in the
// last bit between platform math libraries. Both outputs end with a newline and
// multi-line literals do not, hence the `+ "\n"`. Raw literals (#"""...""")
// keep Markdown's `\|` and JSON's `\n` readable as written.
//
// The ratio digits in the JSON literals were cross-checked against the
// stdlib Python implementation in scripts/verify_vectors.py (same doubles,
// same shortest round-trip text).

@Suite("Report formats")
struct ReportFormatTests {
    /// Three checks in one variant: a regression, an invalid check and a
    /// waived failure, plus one unused waiver and one outdated baseline entry.
    static func housekeeping() throws -> AuditReport {
        let theme = try singleVariantTheme("Housekeeping", variant: "dark",
            pairs: [ColorPair("icon-outline", on: "surface", role: .uiComponent),
                    ColorPair("link", on: "banner", role: .bodyText),
                    ColorPair("hint", on: "surface", role: .bodyText)],
            colors: [("icon-outline", "#4D5964"), ("surface", "#111921"), ("link", "#69B1EC"),
                     ("hint", "#777777")])
        return theme.audit(level: .aa,
            waivers: [Waiver("hint", on: "surface", variant: "dark", reason: "Placeholder text"),
                      Waiver("chip", on: "surface", variant: nil, reason: "Old | chip", expiryNote: "Remove in 2.0")],
            baseline: try Baseline(json: baselineJSON([("dark", "icon-outline", "surface", 2.7916390550241523),
                                                       ("dark", "old", "surface", 2.5)])))
    }

    /// Names, a note and a waiver reason containing `|`, quotes and line
    /// breaks. The waived pair fails body text (3.04), so the report passes.
    static func escaping() throws -> AuditReport {
        let theme = try singleVariantTheme("Pipe | Theme", variant: "light\nmode",
            pairs: [ColorPair("fg|1", on: "bg", role: .bodyText, note: "line one\nline two | more"),
                    ColorPair("plain", on: "bg", role: .bodyText)],
            colors: [("fg|1", "#1E2B37"), ("bg", "#FFFFFF"), ("plain", "#8B959F")])
        return theme.audit(level: .aa,
                           waivers: [Waiver("plain", on: "bg", variant: nil, reason: "Says \"hi\"\r\nthen | bye")])
    }

    /// Three theme problems: a duplicate pair, a malformed palette color and
    /// a baseline recorded at another level.
    static func broken() throws -> AuditReport {
        let theme = Theme("Broken",
            pairs: [ColorPair("text", on: "surface", role: .bodyText),
                    ColorPair("text", on: "surface", role: .largeText)],
            variants: [Variant("light", hex: ["text": "#1E2B37", "surface": "#FFFFFF", "accent": "#12"])])
        return theme.audit(level: .aa, baseline: try Baseline(json: baselineJSON(level: "AAA", [])))
    }

    static func harbor() throws -> AuditReport {
        Harbor.theme.audit(level: .aa, waivers: Harbor.waivers, baseline: try Baseline(json: Harbor.baselineJSON))
    }

    @Test("Hello Markdown: no Note column when no pair has a note")
    func helloMarkdown() {
        #expect(Hello.theme.audit(level: .aa).markdown() == #"""
            ## Contrast audit: Hello (AA)

            Failed: 1 of 2 checks failed (2 pairs x 1 variant).

            | Variant | Foreground | Background | Role | Ratio | Required | Status |
            |---|---|---|---|---|---|---|
            | light | text | surface | body text | 14.42:1 | 4.50:1 | passed |
            | light | hint | surface | body text | 3.04:1 | 4.50:1 | **failed** |
            """# + "\n")
    }

    @Test("Hello JSON")
    func helloJSON() {
        expectJSON(Hello.theme.audit(level: .aa).json(), #"""
            {
              "level" : "AA",
              "outdatedBaselineEntries" : [],
              "passed" : false,
              "problems" : [],
              "results" : [
                {
                  "background" : "surface",
                  "foreground" : "text",
                  "ratio" : 14.423852198732893,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "surface",
                  "foreground" : "hint",
                  "ratio" : 3.044619956587269,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "failed",
                  "variant" : "light"
                }
              ],
              "schemaVersion" : 1,
              "summary" : "Hello at AA: 1 passed, 1 failed, 0 waived, 0 known failures, 0 regressed, 0 invalid.",
              "theme" : "Hello",
              "unusedWaivers" : []
            }
            """# + "\n")
    }

    @Test("Harbor Markdown: every check listed, Note column because one pair has a note")
    func harborMarkdown() throws {
        #expect(try Self.harbor().markdown() == #"""
            ## Contrast audit: Harbor (AA)

            Failed: 2 of 18 checks failed (6 pairs x 3 variants). 1 waived, 1 known failure.

            | Variant | Foreground | Background | Role | Ratio | Required | Status | Note |
            |---|---|---|---|---|---|---|---|
            | light | text | surface | body text | 14.42:1 | 4.50:1 | passed |  |
            | light | subtitle | card | body text | 4.93:1 | 4.50:1 | passed |  |
            | light | link | surface | body text | 5.57:1 | 4.50:1 | passed |  |
            | light | icon-outline | surface | UI component | 2.30:1 | 3.00:1 | **failed** |  |
            | light | caption | glass | body text | 7.59:1 | 4.50:1 | passed |  |
            | light | logo-text | badge | large text | 4.34:1 | 3.00:1 | passed | Wordmark |
            | dark | text | surface | body text | 15.16:1 | 4.50:1 | passed |  |
            | dark | subtitle | card | body text | 3.26:1 | 4.50:1 | **failed** |  |
            | dark | link | surface | body text | 7.68:1 | 4.50:1 | passed |  |
            | dark | icon-outline | surface | UI component | 2.79:1 | 3.00:1 | known failure (baseline 2.79:1) |  |
            | dark | caption | glass | body text | 8.08:1 | 4.50:1 | passed |  |
            | dark | logo-text | badge | large text | 2.90:1 | 3.00:1 | waived: Logotype, exempt under 1.4.3 | Wordmark |
            | increased-contrast | text | surface | body text | 21.00:1 | 4.50:1 | passed |  |
            | increased-contrast | subtitle | card | body text | 12.67:1 | 4.50:1 | passed |  |
            | increased-contrast | link | surface | body text | 8.62:1 | 4.50:1 | passed |  |
            | increased-contrast | icon-outline | surface | UI component | 7.78:1 | 3.00:1 | passed |  |
            | increased-contrast | caption | glass | body text | 18.46:1 | 4.50:1 | passed |  |
            | increased-contrast | logo-text | badge | large text | 6.62:1 | 3.00:1 | passed | Wordmark |
            """# + "\n")
    }

    @Test("Harbor JSON: waived (with expiryNote) and knownFailure fields")
    func harborJSON() throws {
        expectJSON(try Self.harbor().json(), #"""
            {
              "level" : "AA",
              "outdatedBaselineEntries" : [],
              "passed" : false,
              "problems" : [],
              "results" : [
                {
                  "background" : "surface",
                  "foreground" : "text",
                  "ratio" : 14.423852198732893,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "card",
                  "foreground" : "subtitle",
                  "ratio" : 4.933888878984473,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "surface",
                  "foreground" : "link",
                  "ratio" : 5.575440283774227,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "surface",
                  "foreground" : "icon-outline",
                  "ratio" : 2.307640972413328,
                  "required" : 3,
                  "role" : "uiComponent",
                  "status" : "failed",
                  "variant" : "light"
                },
                {
                  "background" : "glass",
                  "foreground" : "caption",
                  "ratio" : 7.597405928290244,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "badge",
                  "foreground" : "logo-text",
                  "note" : "Wordmark",
                  "ratio" : 4.348246415744564,
                  "required" : 3,
                  "role" : "largeText",
                  "status" : "passed",
                  "variant" : "light"
                },
                {
                  "background" : "surface",
                  "foreground" : "text",
                  "ratio" : 15.1620494977794,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "dark"
                },
                {
                  "background" : "card",
                  "foreground" : "subtitle",
                  "ratio" : 3.26785092088523,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "failed",
                  "variant" : "dark"
                },
                {
                  "background" : "surface",
                  "foreground" : "link",
                  "ratio" : 7.680932276110387,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "dark"
                },
                {
                  "background" : "surface",
                  "baselineRatio" : 2.7916390550241523,
                  "foreground" : "icon-outline",
                  "ratio" : 2.7916390550241523,
                  "required" : 3,
                  "role" : "uiComponent",
                  "status" : "knownFailure",
                  "variant" : "dark"
                },
                {
                  "background" : "glass",
                  "foreground" : "caption",
                  "ratio" : 8.081354244858787,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "dark"
                },
                {
                  "background" : "badge",
                  "expiryNote" : "Revisit if the wordmark changes",
                  "foreground" : "logo-text",
                  "note" : "Wordmark",
                  "ratio" : 2.9049976106219595,
                  "required" : 3,
                  "role" : "largeText",
                  "status" : "waived",
                  "variant" : "dark",
                  "waiverReason" : "Logotype, exempt under 1.4.3"
                },
                {
                  "background" : "surface",
                  "foreground" : "text",
                  "ratio" : 21,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                },
                {
                  "background" : "card",
                  "foreground" : "subtitle",
                  "ratio" : 12.676516010307832,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                },
                {
                  "background" : "surface",
                  "foreground" : "link",
                  "ratio" : 8.621803083174647,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                },
                {
                  "background" : "surface",
                  "foreground" : "icon-outline",
                  "ratio" : 7.783242877846501,
                  "required" : 3,
                  "role" : "uiComponent",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                },
                {
                  "background" : "glass",
                  "foreground" : "caption",
                  "ratio" : 18.463495889198,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                },
                {
                  "background" : "badge",
                  "foreground" : "logo-text",
                  "note" : "Wordmark",
                  "ratio" : 6.629933441853581,
                  "required" : 3,
                  "role" : "largeText",
                  "status" : "passed",
                  "variant" : "increased-contrast"
                }
              ],
              "schemaVersion" : 1,
              "summary" : "Harbor at AA: 14 passed, 2 failed, 1 waived, 1 known failure, 0 regressed, 0 invalid.",
              "theme" : "Harbor",
              "unusedWaivers" : []
            }
            """# + "\n")
    }

    @Test("Regressed, invalid and waived rows; unused waivers and outdated entries")
    func housekeepingMarkdown() throws {
        #expect(try Self.housekeeping().markdown() == #"""
            ## Contrast audit: Housekeeping (AA)

            Failed: 2 of 3 checks failed (3 pairs x 1 variant). 1 waived, 0 known failures.

            | Variant | Foreground | Background | Role | Ratio | Required | Status |
            |---|---|---|---|---|---|---|
            | dark | icon-outline | surface | UI component | 2.47:1 | 3.00:1 | **regressed** (baseline 2.79:1, -0.319989) |
            | dark | link | banner | body text | n/a | 4.50:1 | **invalid**: no color named 'banner' in this variant |
            | dark | hint | surface | body text | 3.95:1 | 4.50:1 | waived: Placeholder text |

            Unused waivers:

            - [all variants] 'chip' on 'surface': Old \| chip

            Outdated baseline entries:

            - [dark] 'old' on 'surface' (recorded 2.50:1)
            """# + "\n")
    }

    @Test("baselineRatio, problem, null ratio, waiver without expiryNote, null waiver variant")
    func housekeepingJSON() throws {
        expectJSON(try Self.housekeeping().json(), #"""
            {
              "level" : "AA",
              "outdatedBaselineEntries" : [
                {
                  "background" : "surface",
                  "foreground" : "old",
                  "ratio" : 2.5,
                  "variant" : "dark"
                }
              ],
              "passed" : false,
              "problems" : [],
              "results" : [
                {
                  "background" : "surface",
                  "baselineRatio" : 2.7916390550241523,
                  "foreground" : "icon-outline",
                  "ratio" : 2.4716492891284485,
                  "required" : 3,
                  "role" : "uiComponent",
                  "status" : "regressed",
                  "variant" : "dark"
                },
                {
                  "background" : "banner",
                  "foreground" : "link",
                  "problem" : "no color named 'banner' in this variant",
                  "ratio" : null,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "invalid",
                  "variant" : "dark"
                },
                {
                  "background" : "surface",
                  "foreground" : "hint",
                  "ratio" : 3.9578931805922966,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "waived",
                  "variant" : "dark",
                  "waiverReason" : "Placeholder text"
                }
              ],
              "schemaVersion" : 1,
              "summary" : "Housekeeping at AA: 0 passed, 0 failed, 1 waived, 0 known failures, 1 regressed, 1 invalid.",
              "theme" : "Housekeeping",
              "unusedWaivers" : [
                {
                  "background" : "surface",
                  "expiryNote" : "Remove in 2.0",
                  "foreground" : "chip",
                  "reason" : "Old | chip",
                  "variant" : null
                }
              ]
            }
            """# + "\n")
    }

    @Test("Markdown escapes | and line breaks in names, notes and reasons")
    func escapingMarkdown() throws {
        #expect(try Self.escaping().markdown() == #"""
            ## Contrast audit: Pipe \| Theme (AA)

            Passed: 0 of 2 checks failed (2 pairs x 1 variant). 1 waived, 0 known failures.

            | Variant | Foreground | Background | Role | Ratio | Required | Status | Note |
            |---|---|---|---|---|---|---|---|
            | light<br>mode | fg\|1 | bg | body text | 14.42:1 | 4.50:1 | passed | line one<br>line two \| more |
            | light<br>mode | plain | bg | body text | 3.04:1 | 4.50:1 | waived: Says "hi"<br>then \| bye |  |
            """# + "\n")
    }

    @Test("JSON escapes quotes and control characters and leaves | alone")
    func escapingJSON() throws {
        expectJSON(try Self.escaping().json(), #"""
            {
              "level" : "AA",
              "outdatedBaselineEntries" : [],
              "passed" : true,
              "problems" : [],
              "results" : [
                {
                  "background" : "bg",
                  "foreground" : "fg|1",
                  "note" : "line one\nline two | more",
                  "ratio" : 14.423852198732893,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "passed",
                  "variant" : "light\nmode"
                },
                {
                  "background" : "bg",
                  "foreground" : "plain",
                  "ratio" : 3.044619956587269,
                  "required" : 4.5,
                  "role" : "bodyText",
                  "status" : "waived",
                  "variant" : "light\nmode",
                  "waiverReason" : "Says \"hi\"\r\nthen | bye"
                }
              ],
              "schemaVersion" : 1,
              "summary" : "Pipe | Theme at AA: 1 passed, 0 failed, 1 waived, 0 known failures, 0 regressed, 0 invalid.",
              "theme" : "Pipe | Theme",
              "unusedWaivers" : []
            }
            """# + "\n")
    }

    @Test("Theme problems are listed above the table and in the JSON problems array")
    func problems() throws {
        let report = try Self.broken()
        #expect(report.markdown() == #"""
            ## Contrast audit: Broken (AA)

            Failed: 3 theme problems; 0 of 1 check failed (1 pair x 1 variant).

            Theme problems:

            - pair 'text' on 'surface' is declared more than once; only the first is checked
            - variant 'light' color 'accent' has malformed hex '#12'; expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA
            - baseline was recorded at AAA but this audit runs at AA

            | Variant | Foreground | Background | Role | Ratio | Required | Status |
            |---|---|---|---|---|---|---|
            | light | text | surface | body text | 14.42:1 | 4.50:1 | passed |
            """# + "\n")
        let object = try Self.parse(report.json())
        #expect(object["problems"] as? [String] == report.problems.map(\.description))
        #expect(object["passed"] as? Bool == false)
    }

    @Test("A passing report says Passed")
    func passing() throws {
        let theme = try singleVariantTheme("Hello", variant: "light",
                                           pairs: [ColorPair("text", on: "surface", role: .bodyText)],
                                           colors: [("text", "#1E2B37"), ("surface", "#FFFFFF")])
        let report = theme.audit(level: .aa)
        #expect(report.markdown().hasPrefix("""
            ## Contrast audit: Hello (AA)

            Passed: 0 of 1 check failed (1 pair x 1 variant).

            """))
        #expect(try Self.parse(report.json())["passed"] as? Bool == true)
    }

    @Test("JSON parses with JSONSerialization and has the documented keys")
    func parsesBack() throws {
        let harbor = try Self.parse(Self.harbor().json())
        #expect(Set(harbor.keys) == ["level", "outdatedBaselineEntries", "passed", "problems", "results",
                                     "schemaVersion", "summary", "theme", "unusedWaivers"])
        #expect(harbor["schemaVersion"] as? Int == 1)
        #expect(harbor["theme"] as? String == "Harbor")
        #expect(harbor["level"] as? String == "AA")

        let common: Set<String> = ["background", "foreground", "ratio", "required", "role", "status", "variant"]
        var keysByStatus: [String: Set<String>] = [:]
        for report in [try Self.harbor(), try Self.housekeeping()] {
            let results = try #require(try Self.parse(report.json())["results"] as? [[String: Any]])
            #expect(results.count == report.results.count)
            for result in results {
                let status = try #require(result["status"] as? String)
                keysByStatus[status, default: []].formUnion(Set(result.keys).subtracting(common).subtracting(["note"]))
            }
        }
        #expect(keysByStatus == [
            "passed": [], "failed": [], "knownFailure": ["baselineRatio"], "regressed": ["baselineRatio"],
            "waived": ["waiverReason", "expiryNote"], "invalid": ["problem"],
        ])

        // Unrounded ratios survive the round trip exactly through Swift's own
        // parser. Foundation's JSONSerialization on Linux can read a number one
        // bit off, so its values are compared with a tolerance.
        let report = try Self.harbor()
        let written = textAndNumbers(report.json()).numbers
        for value in report.results.compactMap({ $0.ratio?.value }) {
            #expect(written.contains(value), "\(value)")
        }
        let parsed = try #require(harbor["results"] as? [[String: Any]])
        for (result, object) in zip(report.results, parsed) {
            let read = (object["ratio"] as? NSNumber)?.doubleValue
            if let read, let value = result.ratio?.value {
                #expect(abs(read - value) <= 1e-12 * value, "\(read) vs \(value)")
            } else {
                #expect(read == nil && result.ratio == nil)
            }
        }

        let housekeeping = try Self.parse(Self.housekeeping().json())
        let waivers = try #require(housekeeping["unusedWaivers"] as? [[String: Any]])
        #expect(waivers.count == 1)
        #expect(waivers.first?["variant"] is NSNull)
        let entries = try #require(housekeeping["outdatedBaselineEntries"] as? [[String: Any]])
        #expect(entries.map { $0["foreground"] as? String } == ["old"])
    }

    static func parse(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    @Test("expectJSON accepts last-bit noise but catches real differences")
    func expectJSONTolerance() {
        let ratio = 2.307640972413328
        expectJSON("{\"ratio\" : \(ratio.nextUp), \"id\" : \"#1E2B37\"}",
                   "{\"ratio\" : \(ratio), \"id\" : \"#1E2B37\"}")
        withKnownIssue("a different ratio must fail") {
            expectJSON("{\"ratio\" : 2.307641}", "{\"ratio\" : \(ratio)}")
        }
        withKnownIssue("different text must fail") {
            expectJSON("{\"ratio\" : 3}", "{\"value\" : 3}")
        }
        #expect(textAndNumbers("\"pa\\u0001per\" : -1.5e2").numbers == [-150])
    }
}
