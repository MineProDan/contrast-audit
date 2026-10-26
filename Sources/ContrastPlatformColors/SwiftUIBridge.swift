#if canImport(SwiftUI)
public import ContrastCore
public import SwiftUI

extension SRGBColor {
    /// Resolves a SwiftUI `Color` in an explicit environment and converts it
    /// to gamma-encoded sRGB, keeping alpha.
    ///
    /// Uses `Color.resolve(in:)`, which reads only the environment you pass:
    /// set `colorScheme` (and anything else your colors depend on) on an
    /// `EnvironmentValues` value. A view's current environment is never
    /// consulted. `EnvironmentValues()` starts with `colorScheme == .light`.
    ///
    /// Components come from `Color.Resolved.red`, `.green`, `.blue` and
    /// `.opacity`. Per the SwiftUICore documentation in the Xcode 27.1 SDK,
    /// `Color.Resolved` stores its values "in the Linear sRGB color space,
    /// using extended range", as `Float`; `linearRed` and friends are those
    /// linear values, while `red`, `green` and `blue` are "the amount of red
    /// [green, blue] in the color in the sRGB color space", that is gamma
    /// encoded, which is what WCAG's formula expects. They are not clamped:
    /// Display P3 red resolves to red 1.093.
    ///
    /// Precision is limited by SwiftUI, not by this package: values are
    /// `Float`, and SwiftUI's own Display P3 conversion was measured up to
    /// 0.003 per component away from the exact result (DESIGN.md 9.4). For
    /// Display P3 colors, the `NSColor` and `UIColor` bridges are more
    /// accurate. Converted values within 0.002 of 0...1 are moved onto the
    /// boundary (DESIGN.md 9).
    ///
    /// Main actor: `Color.resolve(in:)` is not itself isolated, but for a
    /// color backed by a platform color (`Color(nsColor:)`, `Color(uiColor:)`,
    /// and possibly asset catalog colors) SwiftUI synchronously hops to the
    /// main thread to resolve it. Called from another thread in a process
    /// without a running app, such as `swift test`, that hop never completes:
    /// it was observed to hang in `Update.syncMain`. On the main actor there
    /// is no hop. In Swift Testing, mark the test or suite `@MainActor`.
    ///
    /// - Throws: `ContrastError.componentOutOfRange` for a color outside the
    ///   sRGB gamut; the value is never clamped, so the caller decides what to
    ///   audit instead.
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @MainActor
    public init(resolving color: Color, in environment: EnvironmentValues) throws {
        let resolved = color.resolve(in: environment)
        try self.init(convertedRed: Double(resolved.red), green: Double(resolved.green),
                      blue: Double(resolved.blue), alpha: Double(resolved.opacity))
    }
}
#endif
