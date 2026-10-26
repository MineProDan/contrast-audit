import Foundation

/// An sRGB color with gamma-encoded components in 0...1 and alpha in 0...1.
///
/// Hashable so that tests can compare parsed colors. Not named `RGBColor`:
/// on macOS, AppKit and SwiftUI expose QuickDraw's C struct of that name,
/// which made the bare name ambiguous in type positions.
public struct SRGBColor: Sendable, Hashable {
    /// Gamma-encoded red component, 0...1.
    public let red: Double
    /// Gamma-encoded green component, 0...1.
    public let green: Double
    /// Gamma-encoded blue component, 0...1.
    public let blue: Double
    /// Opacity, 0...1, where 1 is fully opaque.
    public let alpha: Double

    /// Creates a color from components in 0...1.
    ///
    /// - Throws: `ContrastError.componentOutOfRange` if any component is
    ///   non-finite or outside 0...1. Values are never clamped, because a
    ///   value of 1.02 usually means an extended-range color that this package
    ///   cannot audit correctly.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) throws {
        for (name, value) in [("red", red), ("green", green), ("blue", blue), ("alpha", alpha)] {
            // `contains` is false for NaN, so NaN is rejected along with
            // infinities and out-of-range values.
            guard (0.0...1.0).contains(value) else {
                throw ContrastError.componentOutOfRange(component: name, value: value)
            }
        }
        self.init(uncheckedRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Creates a color from 8-bit components. Cannot fail.
    ///
    /// The distinct labels keep integer literals unambiguous:
    /// `SRGBColor(red: 28, ...)` always selects the Double initializer, which
    /// then throws for 28 instead of silently reading it as 28/255.
    public init(red8: UInt8, green8: UInt8, blue8: UInt8, alpha8: UInt8 = 255) {
        self.init(uncheckedRed: Double(red8) / 255,
                  green: Double(green8) / 255,
                  blue: Double(blue8) / 255,
                  alpha: Double(alpha8) / 255)
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` (CSS order, alpha
    /// last).
    ///
    /// The `#` is optional and digits are case-insensitive. `#RGB` expands
    /// each digit (`#1AF` is `#11AAFF`). `AARRGGBB` (alpha first) is not
    /// supported. An 8-digit string is always read as RRGGBBAA, so
    /// alpha-first input cannot be detected; convert it before passing it in.
    ///
    /// - Throws: `ContrastError.malformedHex` for empty input, any other
    ///   length, non-hex characters, whitespace or a `0x` prefix.
    public init(hex: String) throws {
        var scalars = Array(hex.unicodeScalars)
        if scalars.first == "#" {
            scalars.removeFirst()
        }
        // Only ASCII hex digits count. Character.isHexDigit would also
        // accept full-width digits, which no color format uses.
        var digits: [UInt8] = []
        digits.reserveCapacity(scalars.count)
        for scalar in scalars {
            guard let digit = SRGBColor.hexDigitValue(scalar) else {
                throw ContrastError.malformedHex(hex)
            }
            digits.append(digit)
        }

        let bytes: [UInt8]
        switch digits.count {
        case 3, 4:
            // Each short-form digit d stands for the byte 0xdd.
            bytes = digits.map { $0 * 17 }
        case 6, 8:
            bytes = stride(from: 0, to: digits.count, by: 2).map { digits[$0] * 16 + digits[$0 + 1] }
        default:
            throw ContrastError.malformedHex(hex)
        }
        self.init(red8: bytes[0], green8: bytes[1], blue8: bytes[2],
                  alpha8: bytes.count == 4 ? bytes[3] : 255)
    }

    /// Skips validation. Only for values already known to be in 0...1.
    init(uncheckedRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// True when alpha is exactly 1.
    public var isOpaque: Bool {
        alpha == 1
    }

    /// Source-over compositing of `self` on `background`, applied to
    /// gamma-encoded components: the simple alpha compositing formula of W3C
    /// Compositing and Blending Level 1, used on the encoded values (WCAG does
    /// not define transparency; DESIGN.md decision D4).
    ///
    /// Cannot fail. Compositing in linear light gives different results and
    /// is not offered (DESIGN.md decision D4). Over an opaque background the
    /// result is opaque, with alpha exactly 1.
    public func composited(over background: SRGBColor) -> SRGBColor {
        if background.isOpaque {
            // The common case, kept separate so that the result's alpha is
            // exactly 1 rather than a + (1 - a), which can miss 1 by an ulp.
            let a = alpha
            return SRGBColor(uncheckedRed: red * a + background.red * (1 - a),
                            green: green * a + background.green * (1 - a),
                            blue: blue * a + background.blue * (1 - a),
                            alpha: 1)
        }
        // General Porter-Duff source-over with non-premultiplied inputs.
        let topWeight = alpha
        let bottomWeight = background.alpha * (1 - alpha)
        let outAlpha = topWeight + bottomWeight
        guard outAlpha > 0 else {
            return SRGBColor(uncheckedRed: 0, green: 0, blue: 0, alpha: 0)
        }
        func mix(_ top: Double, _ bottom: Double) -> Double {
            // A weighted mean of two values in 0...1 stays in 0...1, except
            // for rounding at the last bit, which the clamp removes.
            min(1, max(0, (top * topWeight + bottom * bottomWeight) / outAlpha))
        }
        return SRGBColor(uncheckedRed: mix(red, background.red),
                        green: mix(green, background.green),
                        blue: mix(blue, background.blue),
                        alpha: min(1, outAlpha))
    }

    /// WCAG 2.1 relative luminance (linearization threshold 0.04045).
    ///
    /// - Throws: `ContrastError.translucentColor` when alpha < 1, because the
    ///   luminance of a translucent color depends on what is behind it.
    public func relativeLuminance() throws -> Double {
        guard isOpaque else {
            throw ContrastError.translucentColor(alpha: alpha)
        }
        return luminanceIgnoringAlpha
    }

    /// The luminance formula without the opacity check, for callers that
    /// have already resolved transparency.
    var luminanceIgnoringAlpha: Double {
        0.2126 * SRGBColor.linearize(red)
            + 0.7152 * SRGBColor.linearize(green)
            + 0.0722 * SRGBColor.linearize(blue)
    }

    /// The sRGB transfer function inverse, as WCAG 2.1 defines it.
    ///
    /// WCAG 2.1 used 0.03928 before May 2021; for 8-bit input both constants
    /// pick the same branch (a test checks all 256 values).
    static func linearize(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func hexDigitValue(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 0x30...0x39: return UInt8(scalar.value - 0x30)        // 0-9
        case 0x41...0x46: return UInt8(scalar.value - 0x41 + 10)   // A-F
        case 0x61...0x66: return UInt8(scalar.value - 0x61 + 10)   // a-f
        default: return nil
        }
    }
}
