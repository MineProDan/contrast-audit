/// A configuration mistake found by an audit.
///
/// Theme-level cases appear in `AuditReport.problems`; check-level cases in
/// `CheckResult.Status.invalid`. Problems are data rather than thrown errors,
/// so one run reports every mistake.
public enum AuditProblem: Sendable, Equatable, CustomStringConvertible {
    // Theme level

    /// The theme declares no pairs, so the audit would check nothing.
    case noPairs
    /// The theme declares no variants, so the audit would check nothing.
    case noVariants
    /// Two variants share a name; only the first is audited.
    case duplicateVariant(String)
    /// Two pairs share a foreground and background; only the first is used.
    case duplicatePair(foreground: String, background: String)
    /// A variant defines the same color name twice; the name is unusable.
    case duplicateColorName(variant: String, name: String)
    /// A hex string in a variant could not be parsed; the name is unusable.
    case malformedColor(variant: String, name: String, input: String)
    /// The baseline was recorded at another level; it is ignored.
    case baselineLevelMismatch(baseline: ConformanceLevel, audit: ConformanceLevel)

    // Check level

    /// A pair names a color the variant does not define.
    case missingColor(String)
    /// A pair names a color that is malformed or duplicated in this palette.
    case unusableColor(String)
    /// The background is translucent in this variant and the pair names no
    /// backdrop.
    case missingBackdrop(background: String, alpha: Double)
    /// The pair's backdrop name is not defined in this variant.
    case unknownBackdrop(String)
    /// The pair's backdrop is translucent in this variant; it must be opaque.
    case translucentBackdrop(String, alpha: Double)

    /// A one-line explanation, used after `[theme]` or `invalid:` in the
    /// failure message.
    public var description: String {
        switch self {
        case .noPairs:
            return "theme declares no pairs, so nothing was checked"
        case .noVariants:
            return "theme declares no variants, so nothing was checked"
        case let .duplicateVariant(name):
            return "variant '\(name)' is declared more than once; only the first is audited"
        case let .duplicatePair(foreground, background):
            return "pair '\(foreground)' on '\(background)' is declared more than once; only the first is checked"
        case let .duplicateColorName(variant, name):
            return "variant '\(variant)' defines color '\(name)' more than once; checks that use it are invalid"
        case let .malformedColor(variant, name, input):
            return "variant '\(variant)' color '\(name)' has malformed hex '\(input)'; "
                + "expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA"
        case let .baselineLevelMismatch(baseline, audit):
            return "baseline was recorded at \(baseline.rawValue) but this audit runs at \(audit.rawValue)"
        case let .missingColor(name):
            return "no color named '\(name)' in this variant"
        case let .unusableColor(name):
            return "color '\(name)' is malformed or defined more than once in this variant"
        case let .missingBackdrop(background, alpha):
            return "background '\(background)' is translucent (alpha \(DecimalText.rounded(alpha, decimals: 2))) "
                + "and the pair has no backdrop"
        case let .unknownBackdrop(name):
            return "no backdrop color named '\(name)' in this variant"
        case let .translucentBackdrop(name, alpha):
            return "backdrop '\(name)' is translucent (alpha \(DecimalText.rounded(alpha, decimals: 2))); "
                + "a backdrop must be opaque"
        }
    }
}

/// Errors thrown by the direct APIs: parsing colors, luminance of a
/// translucent color, ratios without a usable backdrop, baseline decoding and
/// the platform color bridges.
/// `Theme.audit` never throws; it reports `AuditProblem`s instead.
public enum ContrastError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The string is not `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`.
    case malformedHex(String)
    /// A component passed to `SRGBColor(red:green:blue:alpha:)` is non-finite
    /// or outside 0...1. `component` is "red", "green", "blue" or "alpha".
    case componentOutOfRange(component: String, value: Double)
    /// Relative luminance was requested for a color with alpha < 1.
    case translucentColor(alpha: Double)
    /// A ratio was requested on a translucent background without a backdrop.
    case missingBackdrop
    /// The backdrop behind a translucent background is itself translucent.
    case translucentBackdrop(alpha: Double)
    /// Baseline JSON is invalid; the associated text says why.
    case malformedBaseline(String)
    /// Baseline JSON declares a schemaVersion this version cannot read.
    case unsupportedBaselineVersion(Int)
    /// A platform color has no single sRGB value: a pattern color, a catalog
    /// color without components, or a color space that cannot be converted.
    /// Thrown by ContrastPlatformColors; the associated text says which.
    case unconvertibleColor(String)

    /// A one-line explanation suitable for a test failure.
    public var description: String {
        switch self {
        case let .malformedHex(input):
            return "malformed hex color '\(input)'; expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA "
                + "(the # is optional, alpha comes last)"
        case let .componentOutOfRange(component, value):
            return "\(component) component is \(value); components must be finite and within 0...1"
        case let .translucentColor(alpha):
            return "relative luminance needs an opaque color, but alpha is \(alpha); "
                + "composite it over its background first"
        case .missingBackdrop:
            return "the background is translucent and no backdrop was given"
        case let .translucentBackdrop(alpha):
            return "the backdrop is translucent (alpha \(alpha)); a backdrop must be opaque"
        case let .malformedBaseline(reason):
            return "malformed baseline: \(reason)"
        case let .unsupportedBaselineVersion(version):
            return "unsupported baseline schemaVersion \(version); this version reads schemaVersion "
                + "\(Baseline.currentSchemaVersion)"
        case let .unconvertibleColor(reason):
            return "cannot convert the color to sRGB: \(reason)"
        }
    }
}
