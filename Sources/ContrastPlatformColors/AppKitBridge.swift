#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
public import ContrastCore

extension SRGBColor {
    /// Resolves an `NSColor` under an explicit appearance and converts it to
    /// gamma-encoded sRGB, keeping alpha and full precision (no 8-bit
    /// rounding).
    ///
    /// Dynamic colors (`NSColor(name:dynamicProvider:)`, asset catalog and
    /// system colors such as `labelColor`) are resolved under `appearance`
    /// only, never under the app's, a window's or the thread's current
    /// appearance. The conversion runs inside
    /// `appearance.performAsCurrentDrawingAppearance`, the non-deprecated
    /// API for this since macOS 11 (setting `NSAppearance.current` was
    /// deprecated in macOS 12). AppKit documents the drawing appearance as
    /// per-thread and that call as saving and restoring the previous one, so
    /// this initializer can run on any thread, including concurrent test
    /// tasks, and is not main-actor isolated.
    ///
    /// sRGB colors are read exactly; other color spaces are converted with
    /// ColorSync. See DESIGN.md 9 for the 0.002 tolerance applied to bridged
    /// values.
    ///
    /// - Parameters:
    ///   - color: Any `NSColor`.
    ///   - appearance: For example `NSAppearance(named: .aqua)` or
    ///     `NSAppearance(named: .darkAqua)`.
    /// - Throws: `ContrastError.componentOutOfRange` for a color outside the
    ///   sRGB gamut, such as saturated Display P3 colors; the value is never
    ///   clamped, so the caller decides what to audit instead.
    ///   `ContrastError.unconvertibleColor` for a pattern color or a catalog
    ///   color with no RGB value under that appearance.
    @available(macOS 11.0, *)
    public init(resolving color: NSColor, appearance: NSAppearance) throws {
        var outcome: Result<Self, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            outcome = Result { try Self(resolvingInCurrentDrawingAppearance: color) }
        }
        guard let outcome else {
            throw ContrastError.unconvertibleColor("the appearance did not run the conversion")
        }
        self = try outcome.get()
    }

    /// Must only be called inside `performAsCurrentDrawingAppearance`.
    @available(macOS 11.0, *)
    private init(resolvingInCurrentDrawingAppearance color: NSColor) throws {
        // usingType resolves catalog and dynamic colors under the current
        // drawing appearance and returns nil for patterns. Checking first
        // matters: `cgColor` of a pattern NSColor silently returns opaque
        // black in a gray color space (observed on macOS 26.6).
        guard let components = color.usingType(.componentBased) else {
            throw ContrastError.unconvertibleColor(
                "the NSColor has no component values (a pattern or a catalog color without RGB values)")
        }
        // Same reason: without a CGColorSpace, `cgColor` would be a fallback.
        guard components.colorSpace.cgColorSpace != nil else {
            throw ContrastError.unconvertibleColor(
                "the NSColor's color space '\(components.colorSpace.localizedName ?? "unnamed")' "
                    + "has no CoreGraphics equivalent")
        }
        try self.init(convertingCGColor: components.cgColor)
    }
}
#endif
