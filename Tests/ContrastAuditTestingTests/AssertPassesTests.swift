import ContrastAuditTesting
import ContrastCore
import XCTest

// How these tests check the failure path of `ContrastAudit.assertPasses`.
//
// A failing theme must make `assertPasses` record an XCTest failure, which
// would normally fail the test that calls it. `XCTExpectFailure` turns that
// around: failures recorded inside its block are reported as "expected"
// instead of failing the test, and, because the options are strict, the
// test fails if the block records no failure at all. So the test passes only
// if the helper really failed.
//
// Expected is not enough, though: any failure would do. The `issueMatcher`
// decides which failures count as expected. It accepts a failure only if
// its text is exactly "failed - " followed by the expected aggregated message
// (XCTFail adds that prefix) and it was recorded at the line of the
// `assertPasses` call in this file. A failure with any other text or location
// is not matched, so it is reported as a normal failure and the test fails.
// The matcher logs each location it accepted, and the test then requires that
// log to be exactly one entry, the call site, which proves exactly one failure
// was recorded. `callLine = #line` sits on the same line as the call, so the
// expected line cannot drift when the file is edited.
//
// XCTExpectFailure exists in Apple's XCTest, but swift-corelibs-xctest on Linux
// may not provide it, so those tests are compiled only where Darwin exists.
// The passing-path tests run everywhere. The exact message text is also
// covered by plain string tests in ContrastCoreTests (MessageTests), which run
// on every platform without any of this machinery.

final class AssertPassesTests: XCTestCase {
    func testPassingThemeRecordsNothing() {
        // If assertPasses recorded a failure here, this test would fail.
        let report = ContrastAudit.assertPasses(Fixtures.calm, level: .aa)
        XCTAssertTrue(report.passed)
        XCTAssertNil(report.failureDescription)
        XCTAssertEqual(report.results.count, 6)
    }

    func testWaiversAndBaselineAreForwardedAndHousekeepingRecordsNothing() throws {
        // The waiver covers Hello's only failure, and the extra waiver and the
        // stale baseline entry are housekeeping, which must not fail the test.
        let waivers = [Waiver("hint", on: "surface", variant: "light", reason: "Placeholder text"),
                       Waiver("gone", on: "surface", variant: nil, reason: "Removed pair")]
        let baseline = try Baseline(json: """
            {"schemaVersion": 1, "level": "AA", "entries": [{"variant": "light", "foreground": "gone",
             "background": "surface", "ratio": 2.5}]}
            """)
        let report = ContrastAudit.assertPasses(Fixtures.hello, level: .aa, waivers: waivers, baseline: baseline)
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.unusedWaivers.map(\.foreground), ["gone"])
        XCTAssertEqual(report.outdatedBaselineEntries.map(\.foreground), ["gone"])
    }

    #if canImport(Darwin)
    func testFailingThemeRecordsOneFailureWithTheExactMessage() {
        var callLine = 0
        let recorded = expectedFailures(withMessage: Fixtures.helloMessage) {
            callLine = #line; ContrastAudit.assertPasses(Fixtures.hello, level: .aa)
        }
        XCTAssertEqual(recorded, [RecordedLocation(filePath: #filePath, line: callLine)])
    }

    func testAggregatedMessageWithWaiverAndBaseline() throws {
        let baseline = try Fixtures.harborBaseline()
        var callLine = 0
        var report: AuditReport?
        let recorded = expectedFailures(withMessage: Fixtures.harborMessage) {
            callLine = #line; report = ContrastAudit.assertPasses(Fixtures.harbor, level: .aa, waivers: Fixtures.harborWaivers, baseline: baseline)
        }
        XCTAssertEqual(recorded, [RecordedLocation(filePath: #filePath, line: callLine)])
        // The returned report is the one the message came from.
        XCTAssertEqual(report?.failureDescription, Fixtures.harborMessage)
    }

    /// Runs `body` inside `XCTExpectFailure`, accepting only failures whose
    /// text is exactly the XCTFail form of `message`, and returns where each
    /// accepted failure was recorded.
    private func expectedFailures(withMessage message: String, _ body: () -> Void) -> [RecordedLocation] {
        let log = LocationLog()
        let options = XCTExpectedFailure.Options()
        // Strict (the default, set here for clarity): no failure in the block
        // fails the test.
        options.isStrict = true
        options.issueMatcher = { issue in
            guard issue.type == .assertionFailure,
                  issue.compactDescription == "failed - " + message,
                  let location = issue.sourceCodeContext.location else {
                return false
            }
            log.append(RecordedLocation(filePath: location.fileURL.path, line: location.lineNumber))
            return true
        }
        XCTExpectFailure("assertPasses must record the aggregated message", options: options, failingBlock: body)
        return log.all
    }
    #endif
}
