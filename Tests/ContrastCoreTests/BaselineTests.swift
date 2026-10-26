import ContrastCore
import Testing

@Suite("Baseline")
struct BaselineTests {
    /// One failing pair: '#777777' on white, body text at AA (4.478...).
    static func failingTheme(variant: String = "v") throws -> Theme {
        try singleVariantTheme(variant: variant, pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                               colors: [("ink", "#777777"), ("paper", "#FFFFFF")])
    }

    static func measured() throws -> Double {
        try ContrastRatio(foreground: hex("#777777"), background: hex("#FFFFFF")).value
    }

    static func audit(recorded: Double, theme: Theme? = nil) throws -> AuditReport {
        let baseline = try Baseline(json: baselineJSON([("v", "ink", "paper", recorded)]))
        return try (theme ?? failingTheme()).audit(level: .aa, baseline: baseline)
    }

    @Test("Fails with no entry: failed")
    func noEntry() throws {
        let baseline = try Baseline(json: baselineJSON([("v", "other", "paper", 2)]))
        let report = try Self.failingTheme().audit(level: .aa, baseline: baseline)
        #expect(report.results.first?.status == .failed)
        #expect(!report.passed)
        #expect(report.outdatedBaselineEntries.map(\.foreground) == ["other"])
    }

    @Test("Fails at the recorded ratio: known failure, not outdated")
    func atRecorded() throws {
        let measured = try Self.measured()
        let report = try Self.audit(recorded: measured)
        guard case let .knownFailure(baseline)? = report.results.first?.status else {
            Issue.record("expected knownFailure, got \(String(describing: report.results.first?.status))")
            return
        }
        #expect(baseline.value == measured)
        #expect(report.passed)
        #expect(report.outdatedBaselineEntries.isEmpty)
        #expect(report.summary == "T at AA: 0 passed, 0 failed, 0 waived, 1 known failure, 0 regressed, 0 invalid.")
    }

    @Test("Tolerance edges around the recorded value",
          arguments: [
            (2e-6, "regressed", false),     // measured is 2e-6 below the recording
            (0.5e-6, "known", false),       // within tolerance below
            (-0.5e-6, "known", false),      // within tolerance above
            (-2e-6, "known", true),         // improved beyond tolerance: outdated
          ])
    func toleranceEdges(_ recordedOffset: Double, _ expected: String, _ outdated: Bool) throws {
        let measured = try Self.measured()
        let recorded = measured + recordedOffset
        let report = try Self.audit(recorded: recorded)
        let status = try #require(report.results.first?.status)
        switch (expected, status) {
        case let ("regressed", .regressed(baseline)), let ("known", .knownFailure(baseline)):
            #expect(baseline.value == recorded)
        default:
            Issue.record("expected \(expected), got \(status)")
        }
        #expect(report.passed == (expected == "known"))
        #expect(report.outdatedBaselineEntries.count == (outdated ? 1 : 0))
    }

    @Test("Passes with an entry: passed, entry outdated")
    func nowPasses() throws {
        let theme = try singleVariantTheme(pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                                           colors: [("ink", "#767676"), ("paper", "#FFFFFF")])
        let report = try Self.audit(recorded: 4.4, theme: theme)
        #expect(report.results.first?.status == .passed)
        #expect(report.outdatedBaselineEntries.count == 1)
        #expect(report.passed)
    }

    @Test("Entry for a check that no longer exists is outdated")
    func noLongerExists() throws {
        let baseline = try Baseline(json: baselineJSON([("v", "ink", "paper", 4.2), ("gone", "ink", "paper", 3),
                                                        ("v", "ink", "removed", 3)]))
        let theme = try singleVariantTheme(pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                                           colors: [("ink", "#767676"), ("paper", "#FFFFFF")])
        let report = theme.audit(level: .aa, baseline: baseline)
        #expect(report.outdatedBaselineEntries.map { "\($0.variant)/\($0.background)" }
            == ["gone/paper", "v/paper", "v/removed"])
        #expect(report.passed)
    }

    @Test("Invalid with an entry: invalid, fails, entry not outdated")
    func invalidCheck() throws {
        let theme = try singleVariantTheme(pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                                           colors: [("ink", "#777777")])
        let report = try Self.audit(recorded: 4.4, theme: theme)
        #expect(report.results.first?.status == .invalid(.missingColor("paper")))
        #expect(!report.passed)
        #expect(report.outdatedBaselineEntries.isEmpty)
    }

    @Test("A waiver wins over a baseline entry, which becomes outdated")
    func waiverWins() throws {
        let waiver = Waiver("ink", on: "paper", variant: nil, reason: "Decorative")
        let baseline = try Baseline(json: baselineJSON([("v", "ink", "paper", Self.measured())]))
        let report = try Self.failingTheme().audit(level: .aa, waivers: [waiver], baseline: baseline)
        #expect(report.results.first?.status == .waived(waiver))
        #expect(report.outdatedBaselineEntries.count == 1)
        #expect(report.unusedWaivers.isEmpty)
    }

    @Test("A baseline recorded at another level is ignored and fails the audit")
    func levelMismatch() throws {
        let baseline = try Baseline(json: baselineJSON(level: "AAA", [("v", "ink", "paper", Self.measured())]))
        #expect(baseline.level == .aaa)
        let report = try Self.failingTheme().audit(level: .aa, baseline: baseline)
        #expect(report.problems == [.baselineLevelMismatch(baseline: .aaa, audit: .aa)])
        #expect(report.results.first?.status == .failed)
        #expect(report.outdatedBaselineEntries.isEmpty)
        #expect(!report.passed)
    }

    @Test("Theme problems are never recorded, so a baseline cannot hide them")
    func recordingWithProblems() throws {
        let theme = Theme("T", pairs: [ColorPair("ink", on: "paper", role: .bodyText)],
                          variants: [Variant("v", hex: ["ink": "#777777", "paper": "#FFFFFF"]),
                                     Variant("v", hex: ["ink": "#000000", "paper": "#FFFFFF"])])
        let first = theme.audit(level: .aa)
        #expect(first.problems == [.duplicateVariant("v")])
        let baseline = Baseline(recording: first)
        #expect(baseline.entries.map { "\($0.variant)/\($0.foreground)" } == ["v/ink"])

        let again = theme.audit(level: .aa, baseline: baseline)
        #expect(again.results.map(\.status) == [.knownFailure(baseline: try #require(first.results[0].ratio))])
        #expect(again.problems == [.duplicateVariant("v")])
        #expect(!again.passed)
    }

    @Test("Recording keeps failed, known and regressed checks, sorted; not waived or invalid")
    func recording() throws {
        let pairs = [ColorPair("zeta", on: "paper", role: .bodyText),
                     ColorPair("alpha", on: "paper", role: .bodyText),
                     ColorPair("waived", on: "paper", role: .bodyText),
                     ColorPair("missing", on: "nowhere", role: .bodyText),
                     ColorPair("good", on: "paper", role: .bodyText)]
        let palette: KeyValuePairs<String, String> = ["zeta": "#777777", "alpha": "#888888", "waived": "#999999",
                                                      "missing": "#000000", "good": "#000000", "paper": "#FFFFFF"]
        let theme = Theme("T", pairs: pairs, variants: [Variant("second", hex: palette),
                                                        Variant("first", hex: palette)])
        let waiver = Waiver("waived", on: "paper", variant: nil, reason: "Decorative")
        let first = theme.audit(level: .aa, waivers: [waiver])
        let baseline = Baseline(recording: first)
        #expect(baseline.level == .aa)
        #expect(baseline.entries.map { "\($0.variant)/\($0.foreground)" }
            == ["first/alpha", "first/zeta", "second/alpha", "second/zeta"])

        // Re-recording a report with known failures and a regression keeps them.
        let worse = Theme("T", pairs: pairs, variants: [
            Variant("second", hex: ["zeta": "#999999", "alpha": "#888888", "waived": "#999999",
                                    "missing": "#000000", "good": "#000000", "paper": "#FFFFFF"]),
            Variant("first", hex: palette),
        ])
        let second = worse.audit(level: .aa, waivers: [waiver], baseline: baseline)
        #expect(second.results.contains { if case .regressed = $0.status { return true } else { return false } })
        #expect(Baseline(recording: second).entries.count == 4)
    }

    @Test("JSON round-trip preserves every entry")
    func roundTrip() throws {
        let report = Harbor.theme.audit(level: .aa, waivers: Harbor.waivers)
        let baseline = Baseline(recording: report)
        #expect(baseline.entries.count == 3)
        #expect(try Baseline(json: baseline.json()) == baseline)
    }

    @Test("JSON output is pretty-printed with sorted keys and a trailing newline")
    func exactJSON() throws {
        let report = Harbor.theme.audit(level: .aa, waivers: Harbor.waivers)
        expectJSON(Baseline(recording: report).json(), """
            {
              "entries" : [
                {
                  "background" : "surface",
                  "foreground" : "icon-outline",
                  "ratio" : 2.7916390550241523,
                  "variant" : "dark"
                },
                {
                  "background" : "card",
                  "foreground" : "subtitle",
                  "ratio" : 3.26785092088523,
                  "variant" : "dark"
                },
                {
                  "background" : "surface",
                  "foreground" : "icon-outline",
                  "ratio" : 2.307640972413328,
                  "variant" : "light"
                }
              ],
              "level" : "AA",
              "schemaVersion" : 1
            }

            """)
        let empty = try Baseline(json: baselineJSON(level: "AAA", []))
        #expect(empty.json() == "{\n  \"entries\" : [],\n  \"level\" : \"AAA\",\n  \"schemaVersion\" : 1\n}\n")
    }

    @Test("Names with quotes, backslashes and control characters survive a round-trip")
    func escaping() throws {
        let theme = try singleVariantTheme(variant: "da\"rk\\", pairs: [ColorPair("in\nk", on: "pa\u{1}per", role: .bodyText)],
                                           colors: [("in\nk", "#777777"), ("pa\u{1}per", "#FFFFFF")])
        let baseline = Baseline(recording: theme.audit(level: .aa))
        #expect(baseline.json().contains("\"da\\\"rk\\\\\""))
        #expect(baseline.json().contains("\"pa\\u0001per\""))
        #expect(try Baseline(json: baseline.json()) == baseline)
    }

    @Test("Parsed entries are sorted")
    func parsedSorted() throws {
        let baseline = try Baseline(json: baselineJSON([("b", "x", "y", 2), ("a", "z", "y", 2), ("a", "x", "z", 2),
                                                        ("a", "x", "y", 2)]))
        #expect(baseline.entries.map { "\($0.variant)\($0.foreground)\($0.background)" }
            == ["axy", "axz", "azy", "bxy"])
    }

    @Test("Any schemaVersion other than 1 is rejected", arguments: [0, 2, 99])
    func unsupportedVersion(_ version: Int) {
        #expect(throws: ContrastError.unsupportedBaselineVersion(version)) {
            try Baseline(json: baselineJSON(version: version, []))
        }
    }

    static let malformed: [(String, String)] = [
        ("", "not valid JSON"),
        ("not json", "not valid JSON"),
        ("[]", "wrong type or null value"),
        ("{\"level\": \"AA\", \"entries\": []}", "missing field 'schemaVersion'"),
        ("{\"schemaVersion\": \"1\", \"level\": \"AA\", \"entries\": []}", "wrong type or null value at schemaVersion"),
        ("{\"schemaVersion\": 1, \"entries\": []}", "missing field 'level'"),
        ("{\"schemaVersion\": 1, \"level\": \"AA\"}", "missing field 'entries'"),
        ("{\"schemaVersion\": 1, \"level\": \"A\", \"entries\": []}", "unknown level 'A'; expected 'AA' or 'AAA'"),
        ("{\"schemaVersion\": 1, \"level\": \"AA\", \"entries\": [{\"variant\": \"v\", \"foreground\": \"a\", \"background\": \"b\"}]}",
         "missing field 'ratio' at entries.0"),
        ("{\"schemaVersion\": 1, \"level\": \"AA\", \"entries\": [{\"variant\": \"v\", \"foreground\": \"a\", \"background\": \"b\", \"ratio\": \"2\"}]}",
         "wrong type or null value at entries.0.ratio"),
        (baselineJSON([("v", "a", "b", 0.5)]), "entry 0 has ratio 0.5; ratios must be within 1...21"),
        (baselineJSON([("v", "a", "b", 2), ("v", "a", "c", 22)]), "entry 1 has ratio 22.0; ratios must be within 1...21"),
        (baselineJSON([("v", "a", "b", 2), ("v", "a", "b", 3)]), "duplicate entry for [v] 'a' on 'b'"),
    ]

    @Test("Malformed baselines throw with a reason", arguments: malformed)
    func malformedBaseline(_ json: String, _ reason: String) {
        #expect(throws: ContrastError.malformedBaseline(reason)) {
            try Baseline(json: json)
        }
    }

    @Test("Constants")
    func constants() {
        #expect(Baseline.currentSchemaVersion == 1)
        #expect(Baseline.tolerance == 1e-6)
    }
}
