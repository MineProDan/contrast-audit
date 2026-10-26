// watchOS has UIColor but no `resolvedColor(with:)` and no dynamic colors.
#if canImport(UIKit) && !os(watchOS)
public import ContrastCore
public import UIKit

extension SRGBColor {
    /// Resolves a `UIColor` with an explicit trait collection and converts it
    /// to gamma-encoded sRGB, keeping alpha and full precision (no 8-bit
    /// rounding).
    ///
    /// Dynamic colors (`UIColor { traits in ... }`, asset catalog and system
    /// colors) are resolved with `resolvedColor(with:)` against
    /// `traitCollection` only, never against `UITraitCollection.current`.
    /// Build it with the traits that matter to your theme, for example
    /// `UITraitCollection(userInterfaceStyle: .dark)`, combined with
    /// `accessibilityContrast: .high` for an increased-contrast variant.
    ///
    /// sRGB and extended-sRGB colors (what `UIColor(red:green:blue:alpha:)`
    /// creates) are read exactly; other color spaces are converted with
    /// ColorSync. See DESIGN.md 9 for the 0.002 tolerance applied to bridged
    /// values.
    ///
    /// - Throws: `ContrastError.componentOutOfRange` for a color outside the
    ///   sRGB gamut, such as saturated Display P3 colors or extended-sRGB
    ///   components outside 0...1; the value is never clamped, so the caller
    ///   decides what to audit instead. `ContrastError.unconvertibleColor`
    ///   for a pattern color.
    public init(resolving color: UIColor, with traitCollection: UITraitCollection) throws {
        try self.init(convertingCGColor: color.resolvedColor(with: traitCollection).cgColor)
    }
}
#endif
