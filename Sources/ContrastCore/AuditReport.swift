/// The result of `Theme.audit`. All output formats come from it.
public struct AuditReport: Sendable {
    /// The audited theme's name.
    public let themeName: String
    /// The level every check was evaluated at.
    public let level: ConformanceLevel
    /// Variant declaration order, then pair declaration order.
    public let results: [CheckResult]
    /// Theme-level problems, in the order found.
    public let problems: [AuditProblem]
    /// Waivers that matched no failing check.
    public let unusedWaivers: [Waiver]
    /// Baseline entries whose check now passes, is waived, improved beyond
    /// the tolerance, or no longer exists. Re-record to tighten the baseline.
    public let outdatedBaselineEntries: [Baseline.Entry]

    /// Distinct pairs and variants audited, for the "(p pairs x v variants)"
    /// part of the header. Kept separately because with no variants there
    /// are no results to count pairs from.
    let pairCount: Int
    let variantCount: Int

    init(themeName: String, level: ConformanceLevel, results: [CheckResult],
         problems: [AuditProblem], unusedWaivers: [Waiver],
         outdatedBaselineEntries: [Baseline.Entry], pairCount: Int, variantCount: Int) {
        self.themeName = themeName
        self.level = level
        self.results = results
        self.problems = problems
        self.unusedWaivers = unusedWaivers
        self.outdatedBaselineEntries = outdatedBaselineEntries
        self.pairCount = pairCount
        self.variantCount = variantCount
    }

    /// False if any check failed, regressed or is invalid, or if `problems`
    /// is not empty. Unused waivers and outdated entries do not fail.
    public var passed: Bool {
        problems.isEmpty && !results.contains { $0.status.countsAsFailure }
    }

    /// One line of counts, always present, for example
    /// `Harbor at AA: 14 passed, 2 failed, 1 waived, 1 known failure, 0 regressed, 0 invalid.`
    /// When the theme has problems, their count is appended before the period.
    public var summary: String {
        let counts = Counts(results)
        var text = "\(themeName) at \(level.rawValue): \(counts.passed) passed, \(counts.failed) failed, "
            + "\(counts.waived) waived, \(plural(counts.known, "known failure", "known failures")), "
            + "\(counts.regressed) regressed, \(counts.invalid) invalid"
        if !problems.isEmpty {
            text += ", " + plural(problems.count, "theme problem", "theme problems")
        }
        return text + "."
    }

    /// The aggregated failure message (DESIGN.md 6.1), or nil when `passed`.
    ///
    /// Theme problems come first, then failing, regressed and invalid checks
    /// in declaration order. Waived checks and known failures are counted in
    /// a footer but not listed, which keeps CI logs short.
    public var failureDescription: String? {
        guard !passed else {
            return nil
        }
        let counts = Counts(results)
        var lines = ["Contrast audit failed for theme '\(themeName)' at \(level.rawValue): " + countsSentence]

        for problem in problems {
            lines.append("  [theme] \(problem)")
        }
        for result in results {
            if let line = failureLine(result) {
                lines.append(line)
            }
        }

        // Only non-zero counts are named, so a run without a baseline never
        // mentions one.
        var notCounted: [String] = []
        if counts.waived > 0 {
            notCounted.append("\(counts.waived) waived")
        }
        if counts.known > 0 {
            notCounted.append("\(plural(counts.known, "known failure", "known failures")) (baseline)")
        }
        if !notCounted.isEmpty {
            lines.append("Not counted as failures: " + notCounted.joined(separator: ", ") + ".")
        }
        var housekeeping: [String] = []
        if !unusedWaivers.isEmpty {
            housekeeping.append(plural(unusedWaivers.count, "unused waiver", "unused waivers"))
        }
        if !outdatedBaselineEntries.isEmpty {
            housekeeping.append(plural(outdatedBaselineEntries.count, "outdated baseline entry",
                                       "outdated baseline entries"))
        }
        if !housekeeping.isEmpty {
            lines.append("Housekeeping: " + housekeeping.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// "2 of 18 checks failed (6 pairs x 3 variants).", prefixed with the
    /// theme problem count when there are any. Shared by the failure message
    /// and the Markdown report so the two never disagree.
    var countsSentence: String {
        let counts = Counts(results)
        let failing = counts.failed + counts.regressed + counts.invalid
        var sentence = "\(failing) of \(plural(results.count, "check", "checks")) failed "
            + "(\(plural(pairCount, "pair", "pairs")) x \(plural(variantCount, "variant", "variants")))."
        if !problems.isEmpty {
            sentence = plural(problems.count, "theme problem", "theme problems") + "; " + sentence
        }
        return sentence
    }

    private func failureLine(_ result: CheckResult) -> String? {
        let prefix = "  [\(result.variant)] '\(result.pair.foreground)' on '\(result.pair.background)'"
        let measured: ContrastRatio
        switch result.status {
        case .passed, .waived, .knownFailure:
            return nil
        case let .invalid(problem):
            return prefix + "  invalid: \(problem)"
        case .failed, .regressed:
            // Valid checks always carry a ratio; the guard only avoids a
            // force-unwrap.
            guard let ratio = result.ratio else {
                return prefix + "  invalid: no ratio"
            }
            measured = ratio
        }

        var line = prefix + "  \(measured)  needs \(result.required) "
            + "(\(level.rawValue), \(result.pair.role.displayName))"
        if case let .regressed(baseline) = result.status {
            let delta = DecimalText.truncated(baseline.value - measured.value, decimals: 6)
            line += ", regressed from baseline \(baseline) (-\(delta))"
        }
        if let best = result.bestPossible, best < result.required {
            line += "; unreachable on this background, best possible \(best)"
        }
        return line
    }
}

/// One check's outcome: one pair evaluated in one variant.
public struct CheckResult: Sendable, Equatable {
    /// How the check ended.
    public enum Status: Sendable, Equatable {
        /// The ratio meets the requirement.
        case passed
        /// Below the requirement, with no waiver or baseline entry.
        case failed
        /// Below the requirement and covered by this waiver. Not a pass.
        case waived(Waiver)
        /// Below the requirement and no worse than the baseline's recorded
        /// ratio (within `Baseline.tolerance`).
        case knownFailure(baseline: ContrastRatio)
        /// Below the requirement and worse than the baseline's recorded ratio
        /// by more than `Baseline.tolerance`.
        case regressed(baseline: ContrastRatio)
        /// The check could not be measured because of a configuration problem.
        case invalid(AuditProblem)

        var countsAsFailure: Bool {
            switch self {
            case .failed, .regressed, .invalid: return true
            case .passed, .waived, .knownFailure: return false
            }
        }
    }

    /// The variant this check ran in.
    public let variant: String
    /// The pair that was checked.
    public let pair: ColorPair
    /// The requirement for the pair's role at the audit level.
    public let required: ContrastRatio
    /// The measured ratio; nil only when the status is `.invalid`.
    public let ratio: ContrastRatio?
    /// The outcome.
    public let status: Status

    /// Best ratio black or white could reach on the resolved background; used
    /// for the "unreachable" hint. nil when the check is invalid.
    let bestPossible: ContrastRatio?
}

/// Status counts over a report's results.
struct Counts {
    var passed = 0
    var failed = 0
    var waived = 0
    var known = 0
    var regressed = 0
    var invalid = 0

    init(_ results: [CheckResult]) {
        for result in results {
            switch result.status {
            case .passed: passed += 1
            case .failed: failed += 1
            case .waived: waived += 1
            case .knownFailure: known += 1
            case .regressed: regressed += 1
            case .invalid: invalid += 1
            }
        }
    }
}

/// `count` followed by the singular or plural noun.
func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
    "\(count) \(count == 1 ? singular : pluralForm)"
}
