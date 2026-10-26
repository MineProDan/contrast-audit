import ContrastCore

// Shared by the three bridges. Everything here is internal; the public API is
// the three `SRGBColor(resolving:...)` initializers.

extension SRGBColor {
    /// How far outside 0...1 a bridged component may land and still count as
    /// in gamut. Applied to every component a bridge produces, because a
    /// platform color may have been converted before the bridge sees it:
    /// `UIColor(displayP3Red:...)` already hands back an extended-sRGB CGColor
    /// with green 1.0000001192 for Display P3 white (observed on the iOS 27
    /// simulator). Components inside 0...1 are never changed, so sRGB colors
    /// still round-trip exactly.
    ///
    /// Why 0.002: the platform converters are not exact, and their noise can
    /// push in-gamut colors a hair outside 0...1. Measured with Xcode 27.1 on
    /// macOS 26.6 (DESIGN.md 9.4):
    /// - ColorSync (CGColor conversion, used for NSColor and UIColor) turns
    ///   white in generic gray, Lab or calibrated RGB into 1.0000001192 (one
    ///   Float32 step above 1), and sRGB colors expressed in Display P3 come
    ///   back up to 0.00063 outside 0...1.
    /// - SwiftUI's `Color.resolve(in:)` turns Display P3 white into red
    ///   1.0000879, and sRGB boundary colors expressed in Display P3 come back
    ///   up to 0.0012 outside 0...1.
    /// A tighter bound would reject in-gamut colors for converter noise. 0.002
    /// is about half of one 8-bit step (1/255), so a color this close to the
    /// boundary is indistinguishable from the boundary at 8-bit precision.
    /// Genuinely wide-gamut colors are far outside it: Display P3 red is red
    /// 1.093, green -0.227 in extended sRGB.
    static let conversionTolerance = 0.002

    /// Creates a color from extended-sRGB components produced by a bridge.
    /// Components within `conversionTolerance` of 0...1 are moved
    /// onto the boundary; anything further out is rejected by the core
    /// initializer. Alpha is not color-converted, so it gets no tolerance.
    ///
    /// - Throws: `ContrastError.componentOutOfRange` for a wide-gamut or
    ///   non-finite result.
    init(convertedRed red: Double, green: Double, blue: Double, alpha: Double) throws {
        func snap(_ value: Double) -> Double {
            if value < 0, value >= -SRGBColor.conversionTolerance {
                return 0
            }
            if value > 1, value <= 1 + SRGBColor.conversionTolerance {
                return 1
            }
            return value
        }
        try self.init(red: snap(red), green: snap(green), blue: snap(blue), alpha: alpha)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension SRGBColor {
    /// Converts a static (already resolved) CGColor to gamma-encoded sRGB.
    ///
    /// A color that is already in sRGB or extended sRGB is read without
    /// conversion: ColorSync's conversion runs in Float32 and would change the
    /// last digits even for an identity conversion (observed error 2.8e-8),
    /// and a caller who wrote sRGB values should get exactly those values
    /// back.
    /// Everything else is converted to extended sRGB, which is unbounded, so
    /// the converter reports out-of-gamut colors instead of mapping them into
    /// gamut.
    ///
    /// - Throws: `ContrastError.unconvertibleColor` for a pattern color, a
    ///   color without a color space, or a failed conversion;
    ///   `ContrastError.componentOutOfRange` for a wide-gamut result.
    init(convertingCGColor color: CGColor) throws {
        guard let space = color.colorSpace else {
            throw ContrastError.unconvertibleColor("the color has no color space")
        }
        guard space.model != .pattern else {
            throw ContrastError.unconvertibleColor("a pattern color has no single color value")
        }
        if let name = space.name as String?,
           name == CGColorSpace.sRGB as String || name == CGColorSpace.extendedSRGB as String,
           let components = color.components, components.count == 4 {
            try self.init(convertedRed: Double(components[0]), green: Double(components[1]),
                          blue: Double(components[2]), alpha: Double(components[3]))
            return
        }
        // Relative colorimetric so that no gamut mapping can move a color.
        // Into an unbounded space the intents gave identical results in the
        // measurements, but the choice should not depend on that.
        guard let target = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let converted = color.converted(to: target, intent: .relativeColorimetric, options: nil),
              let components = converted.components, components.count == 4 else {
            throw ContrastError.unconvertibleColor(
                "conversion to extended sRGB failed (color space model \(space.model.rawValue))")
        }
        try self.init(convertedRed: Double(components[0]), green: Double(components[1]),
                      blue: Double(components[2]), alpha: Double(components[3]))
    }
}
#endif
