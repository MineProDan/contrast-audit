import ContrastCore
import Foundation

/// An independent Display P3 to sRGB reference, so that the conversion tests
/// do not compare the platform against itself.
///
/// Both spaces use the sRGB transfer function and a D65 white point, so the
/// conversion is decode, a 3x3 matrix on linear values, encode. The matrix is
/// derived here from the published chromaticities (sRGB: IEC 61966-2-1;
/// Display P3: DCI-P3 primaries with D65 white, as Apple and CSS Color 4
/// define it) instead of being copied from anywhere.
enum DisplayP3Reference {
    static let d65 = (x: 0.3127, y: 0.3290)
    static let sRGBPrimaries = [(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)]
    static let displayP3Primaries = [(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)]

    /// Gamma-encoded extended sRGB for gamma-encoded Display P3 components.
    static func sRGB(fromDisplayP3 p3: [Double]) -> [Double] {
        let toSRGB = multiply(inverse(rgbToXYZ(sRGBPrimaries)), rgbToXYZ(displayP3Primaries))
        return apply(toSRGB, p3.map(decode)).map(encode)
    }

    // The sRGB transfer function, extended to negative values by symmetry as
    // extended sRGB does.
    static func decode(_ value: Double) -> Double {
        let magnitude = abs(value)
        let linear = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
        return value < 0 ? -linear : linear
    }

    static func encode(_ value: Double) -> Double {
        let magnitude = abs(value)
        let encoded = magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return value < 0 ? -encoded : encoded
    }

    typealias Matrix = [[Double]]

    /// The RGB to XYZ matrix of an RGB space: columns are the primaries'
    /// XYZ, scaled so that RGB (1, 1, 1) maps to the white point with Y = 1.
    static func rgbToXYZ(_ primaries: [(Double, Double)]) -> Matrix {
        let columns = primaries.map { [$0.0 / $0.1, 1, (1 - $0.0 - $0.1) / $0.1] }
        let unscaled: Matrix = (0..<3).map { row in columns.map { $0[row] } }
        let white = [d65.x / d65.y, 1, (1 - d65.x - d65.y) / d65.y]
        let scale = apply(inverse(unscaled), white)
        return unscaled.map { row in (0..<3).map { row[$0] * scale[$0] } }
    }

    static func apply(_ m: Matrix, _ v: [Double]) -> [Double] {
        (0..<3).map { row in (0..<3).reduce(0) { $0 + m[row][$1] * v[$1] } }
    }

    static func multiply(_ a: Matrix, _ b: Matrix) -> Matrix {
        (0..<3).map { row in (0..<3).map { col in (0..<3).reduce(0) { $0 + a[row][$1] * b[$1][col] } } }
    }

    static func inverse(_ m: Matrix) -> Matrix {
        let (a, b, c) = (m[0][0], m[0][1], m[0][2])
        let (d, e, f) = (m[1][0], m[1][1], m[1][2])
        let (g, h, i) = (m[2][0], m[2][1], m[2][2])
        let cofactors: Matrix = [[e * i - f * h, c * h - b * i, b * f - c * e],
                                 [f * g - d * i, a * i - c * g, c * d - a * f],
                                 [d * h - e * g, b * g - a * h, a * e - b * d]]
        let determinant = a * cofactors[0][0] + b * cofactors[1][0] + c * cofactors[2][0]
        return cofactors.map { $0.map { $0 / determinant } }
    }
}

/// A small invented two-variant theme for the end-to-end tests: each color
/// has a light and a dark value. "muted" on "surface" fails AA body text in
/// light and passes in dark.
enum BridgeFixture {
    static let colors: [(name: String, light: String, dark: String)] = [
        ("text", "#1F2A33", "#E8EDF0"),
        ("muted", "#8A949C", "#7D8790"),
        ("accent", "#2F6FB0", "#6FA8E0"),
        ("surface", "#FFFFFF", "#121A20"),
    ]

    static let pairs = [
        ColorPair("text", on: "surface", role: .bodyText),
        ColorPair("muted", on: "surface", role: .bodyText),
        ColorPair("accent", on: "surface", role: .uiComponent),
    ]

    /// The same theme declared directly with hex strings, as the reference.
    static let hexTheme = Theme("Bridge", pairs: pairs, variants: [
        Variant("light", entries: colors.map { ($0.name, rgb($0.light)) }),
        Variant("dark", entries: colors.map { ($0.name, rgb($0.dark)) }),
    ])

    /// The fixture's hex strings are literals in this file, so a parse
    /// failure is a bug in the fixture; black makes any test using it fail
    /// loudly instead of trapping.
    static func rgb(_ hex: String) -> SRGBColor {
        (try? SRGBColor(hex: hex)) ?? SRGBColor(red8: 0, green8: 0, blue8: 0)
    }

    /// Builds the theme from colors produced by a bridge.
    static func theme(resolve: (_ light: SRGBColor, _ dark: SRGBColor, _ variant: String) throws -> SRGBColor)
        rethrows -> Theme {
        var variants: [Variant] = []
        for variant in ["light", "dark"] {
            var entries: [(name: String, color: SRGBColor)] = []
            for color in colors {
                entries.append((color.name, try resolve(rgb(color.light), rgb(color.dark), variant)))
            }
            variants.append(Variant(variant, entries: entries))
        }
        return Theme("Bridge", pairs: pairs, variants: variants)
    }
}

/// The error a closure throws, or nil. Used instead of the `#expect(throws:)`
/// overloads that return the error, which need Swift 6.1, so these tests also
/// build with the Swift 6.0 toolchain the package declares.
func thrownError(_ body: () throws -> Void) -> Error? {
    do {
        try body()
        return nil
    } catch {
        return error
    }
}
