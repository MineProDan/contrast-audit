import ContrastAuditTesting
import ContrastCore
import Testing

// How these tests check the failure path of `ContrastAudit.expectPasses`.
//
// A failing theme must make `expectPasses` record a Swift Testing issue,
// which would normally fail the test that calls it. `withKnownIssue` turns
// that around: issues recorded inside its body are reported as known issues
// instead of failing the test, and, because it is not marked intermittent,
// the test fails if the body records no issue at all. So the test passes only
// if the helper really recorded one.
//
// Known is not enough, though: any issue would do. The `matching:` closure
// decides which issues count as known. It accepts an issue only if its
// comments are exactly one comment equal to the expected aggregated message.
// An issue with any other text is not matched, so it is recorded normally
// and the test fails. The closure logs where each accepted issue was
// recorded, and the test then requires that log to be exactly one entry, the
// `expectPasses` call site in this file, which proves exactly one issue and
// the right source location. `callLine = #line` sits on the same line as the
// call, so the expected line cannot drift when the file is edited.
//
// Unlike XCTExpectFailure, withKnownIssue is part of the open-source Swift
// Testing library on every platform, so these tests are not guarded; Linux CI
// is the first place they run off Apple platforms. The exact message text is
// also covered by plain string tests in ContrastCoreTests (MessageTests),
// which run everywhere without any of this machinery.

@Suite("expectPasses")
struct ExpectPassesTests {
    @Test("A passing theme records nothing")
    func passingThemeRecordsNothing() {
        // If expectPasses recorded an issue here, this test would fail.
        let report = ContrastAudit.expectPasses(Fixtures.calm, level: .aa)
        #expect(report.passed)
        #expect(report.failureDescription == nil)
        #expect(report.results.count == 6)
    }

    @Test("Waivers and baseline are forwarded; housekeeping records nothing")
    func forwardsWaiversAndBaseline() throws {
        let waivers = [Waiver("hint", on: "surface", variant: "light", reason: "Placeholder text"),
                       Waiver("gone", on: "surface", variant: nil, reason: "Removed pair")]
        let baseline = try Baseline(json: """
            {"schemaVersion": 1, "level": "AA", "entries": [{"variant": "light", "foreground": "gone",
             "background": "surface", "ratio": 2.5}]}
            """)
        let report = ContrastAudit.expectPasses(Fixtures.hello, level: .aa, waivers: waivers, baseline: baseline)
        #expect(report.passed)
        #expect(report.unusedWaivers.map(\.foreground) == ["gone"])
        #expect(report.outdatedBaselineEntries.map(\.foreground) == ["gone"])
    }

    @Test("A failing theme records one issue with the exact message at the call site")
    func failingThemeRecordsOneIssue() {
        var callLine = 0
        let recorded = knownIssues(withMessage: Fixtures.helloMessage) {
            callLine = #line; ContrastAudit.expectPasses(Fixtures.hello, level: .aa)
        }
        #expect(recorded == [RecordedLocation(filePath: #filePath, line: callLine)])
    }

    @Test("The aggregated message includes the waiver and baseline footer")
    func aggregatedMessage() throws {
        let baseline = try Fixtures.harborBaseline()
        var callLine = 0
        var report: AuditReport?
        let recorded = knownIssues(withMessage: Fixtures.harborMessage) {
            callLine = #line; report = ContrastAudit.expectPasses(Fixtures.harbor, level: .aa, waivers: Fixtures.harborWaivers, baseline: baseline)
        }
        #expect(recorded == [RecordedLocation(filePath: #filePath, line: callLine)])
        // The returned report is the one the message came from.
        #expect(report?.failureDescription == Fixtures.harborMessage)
    }

    /// Runs `body` inside `withKnownIssue`, accepting only issues whose
    /// single comment is exactly `message`, and returns where each accepted
    /// issue was recorded.
    private func knownIssues(withMessage message: String, sourceLocation: SourceLocation = #_sourceLocation,
                             _ body: () -> Void) -> [RecordedLocation] {
        let log = LocationLog()
        withKnownIssue("expectPasses must record the aggregated message", sourceLocation: sourceLocation) {
            body()
        } matching: { issue in
            guard issue.comments.map(\.rawValue) == [message], let location = issue.sourceLocation else {
                return false
            }
            log.append(RecordedLocation(file: location.fileName, line: location.line))
            return true
        }
        return log.all
    }
}
