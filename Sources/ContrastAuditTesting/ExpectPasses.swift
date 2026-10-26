#if canImport(Testing)
public import ContrastCore
public import Testing

extension ContrastAudit {
    /// Swift Testing equivalent of `assertPasses`: audits `theme` and, if the
    /// report did not pass, records exactly one `Issue` whose comment is the
    /// report's `failureDescription`, at `sourceLocation`. Records nothing on
    /// success.
    ///
    /// Returns the report so that callers can attach `markdown()` or inspect
    /// individual results. Configuration mistakes fail the same way, as
    /// lines in the message, rather than trapping or throwing.
    ///
    /// - Parameters:
    ///   - theme: The pairs and variants to audit.
    ///   - level: The WCAG level to check against. There is no default, so
    ///     every call site states it.
    ///   - waivers: Reviewed exceptions; waived failures do not fail the test.
    ///   - baseline: Known failures that may not get worse.
    ///   - sourceLocation: Defaults to the caller's location; pass it through
    ///     from your own helper so issues point at your caller.
    @discardableResult
    public static func expectPasses(_ theme: Theme, level: ConformanceLevel,
                                    waivers: [Waiver] = [], baseline: Baseline? = nil,
                                    sourceLocation: SourceLocation = #_sourceLocation)
                                    -> AuditReport {
        let report = theme.audit(level: level, waivers: waivers, baseline: baseline)
        if let failure = report.failureDescription {
            // Issue.record rather than #expect, so the issue carries only the
            // aggregated message and not an expanded boolean expression.
            Issue.record(Comment(rawValue: failure), sourceLocation: sourceLocation)
        }
        return report
    }
}
#endif
