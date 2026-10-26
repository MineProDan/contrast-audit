/// A foreground/background relationship, declared once per theme and
/// checked in every variant.
///
/// The audit identifies a pair by (foreground, background): declaring the
/// same two names twice is a theme problem even if the roles differ. The
/// synthesized `==` compares every field, including role, backdrop and note.
public struct ColorPair: Sendable, Hashable {
    /// Name of the foreground color in each variant's palette.
    public let foreground: String
    /// Name of the background color in each variant's palette.
    public let background: String
    /// Decides the required ratio.
    public let role: PairRole
    /// Name of an opaque palette color behind a translucent background.
    /// Looked up only in variants where the background is translucent.
    public let backdrop: String?
    /// Free text shown in Markdown and JSON reports.
    public let note: String?

    /// Declares a pair. Cannot fail; names are resolved during the audit.
    public init(_ foreground: String, on background: String, role: PairRole,
                backdrop: String? = nil, note: String? = nil) {
        self.foreground = foreground
        self.background = background
        self.role = role
        self.backdrop = backdrop
        self.note = note
    }
}

/// A named palette. Duplicate or malformed entries never trap; they are
/// reported by the audit.
public struct Variant: Sendable {
    /// The name shown in brackets in failure messages, such as `[dark]`.
    public let name: String

    /// Palette entries in declaration order, unvalidated until the audit.
    let entries: [Entry]

    struct Entry: Sendable {
        enum Source: Sendable {
            case color(SRGBColor)
            case hex(String)
        }

        let name: String
        let source: Source
    }

    /// Creates a palette from colors. Cannot fail.
    ///
    /// `KeyValuePairs` instead of `Dictionary`: a dictionary literal with a
    /// duplicate key traps at runtime, while this reports it.
    public init(_ name: String, colors: KeyValuePairs<String, SRGBColor>) {
        self.name = name
        self.entries = colors.map { Entry(name: $0.key, source: .color($0.value)) }
    }

    /// Creates a palette from hex strings. Cannot fail.
    ///
    /// Hex strings are parsed during the audit; a malformed one becomes an
    /// `AuditProblem.malformedColor` instead of an error at declaration, so a
    /// theme can be declared without `try` and every typo is reported in one
    /// run.
    public init(_ name: String, hex: KeyValuePairs<String, String>) {
        self.name = name
        self.entries = hex.map { Entry(name: $0.key, source: .hex($0.value)) }
    }

    /// Creates a palette from an array, for palettes built in a loop (for
    /// example from a token enum). Cannot fail.
    public init(_ name: String, entries: [(name: String, color: SRGBColor)]) {
        self.name = name
        self.entries = entries.map { Entry(name: $0.name, source: .color($0.color)) }
    }
}

/// Pairs plus variants: the unit you audit.
public struct Theme: Sendable {
    /// Shown in the failure message header and the summary.
    public let name: String
    /// Every pair is checked in every variant, in this order.
    public let pairs: [ColorPair]
    /// Audited in this order.
    public let variants: [Variant]

    /// Declares a theme. Cannot fail; mistakes are reported by `audit`.
    public init(_ name: String, pairs: [ColorPair], variants: [Variant]) {
        self.name = name
        self.pairs = pairs
        self.variants = variants
    }

    /// Runs every check. Never throws and never traps: configuration
    /// problems become `AuditProblem`s and fail the report.
    ///
    /// Precedence for one check: invalid, then passed, then waiver, then
    /// baseline, then failed. A baseline recorded at another level is
    /// ignored and reported as a theme problem.
    public func audit(level: ConformanceLevel, waivers: [Waiver] = [],
                      baseline: Baseline? = nil) -> AuditReport {
        var problems: [AuditProblem] = []
        if pairs.isEmpty {
            problems.append(.noPairs)
        }
        if variants.isEmpty {
            problems.append(.noVariants)
        }

        var uniqueVariants: [Variant] = []
        var seenVariants: Set<String> = []
        var reportedVariants: Set<String> = []
        for variant in variants {
            if seenVariants.insert(variant.name).inserted {
                uniqueVariants.append(variant)
            } else if reportedVariants.insert(variant.name).inserted {
                problems.append(.duplicateVariant(variant.name))
            }
        }

        var uniquePairs: [ColorPair] = []
        var seenPairs: Set<PairKey> = []
        var reportedPairs: Set<PairKey> = []
        for pair in pairs {
            let key = PairKey(foreground: pair.foreground, background: pair.background)
            if seenPairs.insert(key).inserted {
                uniquePairs.append(pair)
            } else if reportedPairs.insert(key).inserted {
                problems.append(.duplicatePair(foreground: pair.foreground, background: pair.background))
            }
        }

        let palettes = uniqueVariants.map { Palette(resolving: $0, problems: &problems) }

        var activeBaseline = baseline
        if let baseline, baseline.level != level {
            problems.append(.baselineLevelMismatch(baseline: baseline.level, audit: level))
            activeBaseline = nil
        }
        var baselineRatios: [CheckKey: Double] = [:]
        for entry in activeBaseline?.entries ?? [] {
            baselineRatios[CheckKey(entry)] = entry.ratio
        }

        var results: [CheckResult] = []
        var usedWaivers = Array(repeating: false, count: waivers.count)
        var checkedKeys: Set<CheckKey> = []
        var outdatedKeys: Set<CheckKey> = []

        for palette in palettes {
            for pair in uniquePairs {
                let key = CheckKey(variant: palette.name, foreground: pair.foreground,
                                   background: pair.background)
                checkedKeys.insert(key)
                let required = pair.role.requiredRatio(at: level)

                let measurement: Measurement
                switch palette.measure(pair) {
                case let .invalid(problem):
                    results.append(CheckResult(variant: palette.name, pair: pair, required: required,
                                               ratio: nil, status: .invalid(problem), bestPossible: nil))
                    continue
                case let .valid(value):
                    measurement = value
                }

                let ratio = measurement.ratio
                let recorded = baselineRatios[key]
                let status: CheckResult.Status
                if ratio.meets(pair.role, at: level) {
                    status = .passed
                    if recorded != nil {
                        outdatedKeys.insert(key)
                    }
                } else if let index = waivers.firstIndex(where: { $0.matches(key) }) {
                    usedWaivers[index] = true
                    status = .waived(waivers[index])
                    if recorded != nil {
                        outdatedKeys.insert(key)
                    }
                } else if let recorded {
                    let recordedRatio = ContrastRatio(uncheckedValue: recorded)
                    if ratio.value < recorded - Baseline.tolerance {
                        status = .regressed(baseline: recordedRatio)
                    } else {
                        status = .knownFailure(baseline: recordedRatio)
                        if ratio.value > recorded + Baseline.tolerance {
                            outdatedKeys.insert(key)
                        }
                    }
                } else {
                    status = .failed
                }
                results.append(CheckResult(variant: palette.name, pair: pair, required: required,
                                           ratio: ratio, status: status,
                                           bestPossible: measurement.bestPossible))
            }
        }

        let unusedWaivers = zip(waivers, usedWaivers).filter { !$0.1 }.map(\.0)
        let outdated = (activeBaseline?.entries ?? []).filter { entry in
            let key = CheckKey(entry)
            return outdatedKeys.contains(key) || !checkedKeys.contains(key)
        }

        return AuditReport(themeName: name, level: level, results: results, problems: problems,
                           unusedWaivers: unusedWaivers, outdatedBaselineEntries: outdated,
                           pairCount: uniquePairs.count, variantCount: uniqueVariants.count)
    }
}

/// A reviewed exception. Applies to failing checks only; never turns a check
/// into a pass and never hides an invalid check.
public struct Waiver: Sendable, Hashable {
    /// Foreground color name of the waived pair.
    public let foreground: String
    /// Background color name of the waived pair.
    public let background: String
    /// The variant the waiver applies to; nil means every variant.
    public let variant: String?
    /// Why the failure is acceptable, shown in reports.
    public let reason: String
    /// Free text such as "remove after the 2.0 redesign". Not a Date, so
    /// results do not depend on the clock.
    public let expiryNote: String?

    /// Declares a waiver. Cannot fail. A waiver that matches no failing
    /// check is reported in `AuditReport.unusedWaivers`.
    public init(_ foreground: String, on background: String, variant: String?,
                reason: String, expiryNote: String? = nil) {
        self.foreground = foreground
        self.background = background
        self.variant = variant
        self.reason = reason
        self.expiryNote = expiryNote
    }

    func matches(_ key: CheckKey) -> Bool {
        foreground == key.foreground && background == key.background
            && (variant == nil || variant == key.variant)
    }
}

struct PairKey: Hashable {
    let foreground: String
    let background: String
}

struct CheckKey: Hashable {
    let variant: String
    let foreground: String
    let background: String

    init(variant: String, foreground: String, background: String) {
        self.variant = variant
        self.foreground = foreground
        self.background = background
    }

    init(_ entry: Baseline.Entry) {
        self.init(variant: entry.variant, foreground: entry.foreground, background: entry.background)
    }
}

/// Either a value or the problem that prevented it. `Result` needs an
/// `Error` failure type, and `AuditProblem` is data, not an error.
enum Checked<Value> {
    case valid(Value)
    case invalid(AuditProblem)
}

/// A measured, valid check.
struct Measurement {
    let ratio: ContrastRatio
    /// Best ratio any foreground could reach on the resolved background.
    let bestPossible: ContrastRatio
}

/// One variant's colors after parsing, with unusable names marked.
struct Palette {
    let name: String
    private var colors: [String: SRGBColor] = [:]
    private var unusable: Set<String> = []

    init(resolving variant: Variant, problems: inout [AuditProblem]) {
        name = variant.name
        var seen: Set<String> = []
        var reportedDuplicates: Set<String> = []
        for entry in variant.entries {
            if !seen.insert(entry.name).inserted {
                unusable.insert(entry.name)
                colors[entry.name] = nil
                if reportedDuplicates.insert(entry.name).inserted {
                    problems.append(.duplicateColorName(variant: variant.name, name: entry.name))
                }
                // A duplicated name is unusable whatever its value, so its value is
                // not parsed; that would only add a second problem for one mistake.
                continue
            }
            let color: SRGBColor
            switch entry.source {
            case let .color(value):
                color = value
            case let .hex(text):
                guard let parsed = try? SRGBColor(hex: text) else {
                    problems.append(.malformedColor(variant: variant.name, name: entry.name, input: text))
                    unusable.insert(entry.name)
                    continue
                }
                color = parsed
            }
            if !unusable.contains(entry.name) {
                colors[entry.name] = color
            }
        }
    }

    private func lookup(_ colorName: String) -> Checked<SRGBColor> {
        if unusable.contains(colorName) {
            return .invalid(.unusableColor(colorName))
        }
        guard let color = colors[colorName] else {
            return .invalid(.missingColor(colorName))
        }
        return .valid(color)
    }

    /// Applies DESIGN.md 5.3: resolve the background (over the backdrop if
    /// translucent), then composite a translucent foreground over it.
    func measure(_ pair: ColorPair) -> Checked<Measurement> {
        let foreground: SRGBColor
        let background: SRGBColor
        switch (lookup(pair.foreground), lookup(pair.background)) {
        case let (.invalid(problem), _), let (_, .invalid(problem)):
            return .invalid(problem)
        case let (.valid(fg), .valid(bg)):
            foreground = fg
            background = bg
        }

        var resolved = background
        if !background.isOpaque {
            guard let backdropName = pair.backdrop else {
                return .invalid(.missingBackdrop(background: pair.background, alpha: background.alpha))
            }
            let backdrop: SRGBColor
            switch lookup(backdropName) {
            case .invalid(.missingColor):
                return .invalid(.unknownBackdrop(backdropName))
            case let .invalid(problem):
                return .invalid(problem)
            case let .valid(color):
                backdrop = color
            }
            guard backdrop.isOpaque else {
                return .invalid(.translucentBackdrop(backdropName, alpha: backdrop.alpha))
            }
            resolved = background.composited(over: backdrop)
        }

        return .valid(Measurement(ratio: ContrastRatio.between(foreground, onOpaque: resolved),
                                    bestPossible: ContrastRatio.bestPossible(onOpaque: resolved)))
    }
}
