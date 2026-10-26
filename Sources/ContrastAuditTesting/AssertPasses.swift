#if canImport(XCTest)
public import ContrastCore
import XCTest

extension ContrastAudit {
    /// Audits `theme` and, if the report did not pass, records exactly one
    /// XCTest failure whose message is the report's `failureDescription`,
    /// attributed to the caller's file and line. Records nothing on success.
    ///
    /// Returns the report so that callers can attach `markdown()` or inspect
    /// individual results. Configuration mistakes (a missing color, a
    /// malformed hex string, a baseline recorded at another level) fail the
    /// same way, as lines in the message, rather than trapping or throwing.
    ///
    /// - Parameters:
    ///   - theme: The pairs and variants to audit.
    ///   - level: The WCAG level to check against. There is no default, so
    ///     every call site states it.
    ///   - waivers: Reviewed exceptions; waived failures do not fail the test.
    ///   - baseline: Known failures that may not get worse.
    ///   - file: Defaults to the caller's file; pass it through from your own
    ///     helper so failures point at your caller.
    ///   - line: Defaults to the caller's line.
    @discardableResult
    public static func assertPasses(_ theme: Theme, level: ConformanceLevel,
                                    waivers: [Waiver] = [], baseline: Baseline? = nil,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) -> AuditReport {
        let report = theme.audit(level: level, waivers: waivers, baseline: baseline)
        if let failure = report.failureDescription {
            // One XCTFail for the whole theme, not one per pair, so the CI log
            // shows a single aggregated message.
            XCTFail(failure, file: file, line: line)
        }
        return report
    }
}
#endif
