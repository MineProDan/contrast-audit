/// A WCAG contrast ratio, 1...21.
///
/// Stores the unrounded value. There is no public initializer from a raw
/// Double, so every ratio a caller sees was computed by this library or is a
/// WCAG requirement.
public struct ContrastRatio: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The unrounded ratio. All comparisons use this value.
    public let value: Double

    /// Computes the ratio for a foreground drawn on a background.
    ///
    /// A translucent foreground is composited over the background. A
    /// translucent background is first composited over `backdrop`. The
    /// backdrop is ignored when the background is opaque.
    ///
    /// - Throws: `ContrastError.missingBackdrop` if the background is
    ///   translucent and `backdrop` is nil; `ContrastError.translucentBackdrop`
    ///   if the background is translucent and the backdrop is translucent too.
    public init(foreground: SRGBColor, background: SRGBColor, backdrop: SRGBColor? = nil) throws {
        var resolvedBackground = background
        if !background.isOpaque {
            guard let backdrop else {
                throw ContrastError.missingBackdrop
            }
            guard backdrop.isOpaque else {
                throw ContrastError.translucentBackdrop(alpha: backdrop.alpha)
            }
            resolvedBackground = background.composited(over: backdrop)
        }
        self = ContrastRatio.between(foreground, onOpaque: resolvedBackground)
    }

    /// For WCAG requirements and values recorded in a baseline, which are
    /// already validated or are constants.
    init(uncheckedValue value: Double) {
        self.value = value
    }

    /// The ratio of `foreground` (composited if translucent) on a background
    /// the caller has already made opaque.
    static func between(_ foreground: SRGBColor, onOpaque background: SRGBColor) -> ContrastRatio {
        let top = foreground.isOpaque ? foreground : foreground.composited(over: background)
        let first = top.luminanceIgnoringAlpha
        let second = background.luminanceIgnoringAlpha
        let lighter = max(first, second)
        let darker = min(first, second)
        return ContrastRatio(uncheckedValue: (lighter + 0.05) / (darker + 0.05))
    }

    /// The highest ratio any opaque foreground can reach on an opaque
    /// background: black or white, whichever is further away.
    static func bestPossible(onOpaque background: SRGBColor) -> ContrastRatio {
        let black = SRGBColor(red8: 0, green8: 0, blue8: 0)
        let white = SRGBColor(red8: 255, green8: 255, blue8: 255)
        return max(between(black, onOpaque: background), between(white, onOpaque: background))
    }

    /// Truncated to two decimals, never rounded up: 4.499... prints "4.49:1".
    ///
    /// Locale-independent.
    public var description: String {
        DecimalText.truncated(value, decimals: 2) + ":1"
    }

    /// `value >= role.requiredRatio(at: level).value`, unrounded.
    public func meets(_ role: PairRole, at level: ConformanceLevel) -> Bool {
        value >= role.requiredRatio(at: level).value
    }

    /// Orders by the unrounded value.
    public static func < (lhs: ContrastRatio, rhs: ContrastRatio) -> Bool {
        lhs.value < rhs.value
    }
}

/// What a pair is, which decides its WCAG requirement. No default.
public enum PairRole: String, Sendable, CaseIterable {
    /// Text below the large-scale size (SC 1.4.3 / 1.4.6).
    case bodyText
    /// At least 18pt, or at least 14pt bold, in WCAG's units (see DESIGN.md 2.4).
    case largeText
    /// UI components and graphical objects (SC 1.4.11). 3:1 at AA and AAA.
    case uiComponent

    /// The minimum ratio for this role: AA 4.5 / 3 / 3, AAA 7 / 4.5 / 3
    /// (body text / large text / UI component). Cannot fail.
    public func requiredRatio(at level: ConformanceLevel) -> ContrastRatio {
        switch (self, level) {
        case (.bodyText, .aa): return ContrastRatio(uncheckedValue: 4.5)
        case (.bodyText, .aaa): return ContrastRatio(uncheckedValue: 7)
        case (.largeText, .aa): return ContrastRatio(uncheckedValue: 3)
        case (.largeText, .aaa): return ContrastRatio(uncheckedValue: 4.5)
        // SC 1.4.11 exists only at AA, so AAA keeps the same 3:1 (decision D3).
        case (.uiComponent, _): return ContrastRatio(uncheckedValue: 3)
        }
    }

    /// The words used in failure messages and reports.
    var displayName: String {
        switch self {
        case .bodyText: return "body text"
        case .largeText: return "large text"
        case .uiComponent: return "UI component"
        }
    }
}

/// A WCAG conformance level. One audit runs at one level.
public enum ConformanceLevel: String, Sendable, CaseIterable {
    /// Level AA: SC 1.4.3 and 1.4.11.
    case aa = "AA"
    /// Level AAA: SC 1.4.6, plus 1.4.11 at its AA value.
    case aaa = "AAA"
}

/// Locale-independent decimal formatting built from integers, so output never
/// depends on the user's locale or on Foundation's formatters.
enum DecimalText {
    /// Prints the largest `decimals`-place number that, read back as a
    /// Double, does not exceed `value`, for non-negative finite values. So the
    /// display never exceeds the value, and a value such as 1.13 (stored as
    /// 1.1299...) still prints "1.13" rather than "1.12".
    static func truncated(_ value: Double, decimals: Int) -> String {
        // Only library-computed values reach this (ratios, deltas, alpha),
        // so the fallback exists to avoid a trap, not as a display format.
        guard value.isFinite, value >= 0, value < 1e9 else {
            return "\(value)"
        }
        let scale = power10(decimals)
        var count = (value * scale).rounded(.down)
        // The multiplication can land one step off in either direction near
        // a step (DESIGN.md 6.2), so correct it against the stored value.
        if count / scale > value {
            count -= 1
        } else if (count + 1) / scale <= value {
            count += 1
        }
        return format(count, decimals: decimals)
    }

    /// Rounds half away from zero to `decimals` places, for values such as
    /// alpha where truncation would not matter for pass or fail.
    static func rounded(_ value: Double, decimals: Int) -> String {
        // Only library-computed values reach this (ratios, deltas, alpha),
        // so the fallback exists to avoid a trap, not as a display format.
        guard value.isFinite, value >= 0, value < 1e9 else {
            return "\(value)"
        }
        return format((value * power10(decimals)).rounded(), decimals: decimals)
    }

    private static func power10(_ exponent: Int) -> Double {
        var result = 1.0
        for _ in 0..<exponent {
            result *= 10
        }
        return result
    }

    private static func format(_ count: Double, decimals: Int) -> String {
        // Values here are at most a few million, far inside Int's range.
        let units = Int(count)
        var scale = 1
        for _ in 0..<decimals {
            scale *= 10
        }
        let whole = String(units / scale)
        guard decimals > 0 else {
            return whole
        }
        var fraction = String(units % scale)
        while fraction.count < decimals {
            fraction = "0" + fraction
        }
        return whole + "." + fraction
    }
}
