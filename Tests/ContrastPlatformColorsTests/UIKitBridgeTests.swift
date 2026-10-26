#if canImport(UIKit) && !os(watchOS)
import ContrastCore
import ContrastPlatformColors
import Testing
import UIKit

/// A dynamic UIColor that is `light` in the light style and `dark` in the
/// dark style.
private func dynamicColor(light: SRGBColor, dark: SRGBColor) -> UIColor {
    UIColor { traits in
        let color = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
private let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

// Not main-actor isolated on purpose: these tests run on Swift Testing's
// cooperative pool, which shows that resolvedColor(with:) needs no main thread.
@Suite("UIColor bridge")
struct UIKitBridgeTests {
    static let light = try? SRGBColor(red: 0.1, green: 0.2, blue: 0.3)
    static let dark = try? SRGBColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.5)

    @Test("Static sRGB colors round-trip exactly with both trait collections",
          arguments: [(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.123456789, 0.5, 0.987654321, 1.0),
                      (28.0 / 255, 118.0 / 255, 1e-9, 0.25)])
    func staticSRGBRoundTrips(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) throws {
        let expected = try SRGBColor(red: red, green: green, blue: blue, alpha: alpha)
        let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #expect(try SRGBColor(resolving: color, with: lightTraits) == expected)
        #expect(try SRGBColor(resolving: color, with: darkTraits) == expected)
    }

    @Test("A dynamic color resolves per trait collection, in either order, and alpha is kept")
    func dynamicColorPerTraits() throws {
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let color = dynamicColor(light: light, dark: dark)
        for traits in [lightTraits, darkTraits, darkTraits, lightTraits, darkTraits] {
            let resolved = try SRGBColor(resolving: color, with: traits)
            #expect(resolved == (traits.userInterfaceStyle == .dark ? dark : light))
        }
    }

    @Test("The current trait collection is ignored")
    func ambientTraitsIgnored() throws {
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let color = dynamicColor(light: light, dark: dark)
        var results: [SRGBColor] = []
        var thrown: (any Error)?
        for (ambient, requested) in [(darkTraits, lightTraits), (lightTraits, darkTraits)] {
            ambient.performAsCurrent {
                do {
                    results.append(try SRGBColor(resolving: color, with: requested))
                } catch {
                    thrown = error
                }
            }
        }
        #expect(thrown == nil)
        #expect(results == [light, dark])
    }

    @Test("Display P3 colors inside sRGB convert to the expected sRGB values",
          arguments: [[0.5, 0.3, 0.2], [0.8, 0.6, 0.4], [0.35, 0.55, 0.75], [0.9, 0.2, 0.15], [1, 1, 1]])
    func displayP3InGamut(_ p3: [Double]) throws {
        let expected = DisplayP3Reference.sRGB(fromDisplayP3: p3)
        let color = UIColor(displayP3Red: p3[0], green: p3[1], blue: p3[2], alpha: 0.75)
        let resolved = try SRGBColor(resolving: color, with: lightTraits)
        // Same tolerance as the NSColor tests (see AppKitBridgeTests). UIKit
        // converts Display P3 to extended sRGB itself; for white it returns
        // green 1.0000001192, which the bridge tolerance absorbs.
        for (actual, wanted) in zip([resolved.red, resolved.green, resolved.blue], expected) {
            #expect(abs(actual - wanted) < 0.001, "\(actual) vs \(wanted)")
        }
        #expect(resolved.alpha == 0.75)
    }

    @Test("Wide-gamut colors throw componentOutOfRange instead of clamping")
    func wideGamutThrows() throws {
        let p3Red = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let error = thrownError {
            _ = try SRGBColor(resolving: p3Red, with: lightTraits)
        } as? ContrastError
        guard case let .componentOutOfRange("red", value)? = error else {
            Issue.record("expected componentOutOfRange for red, got \(String(describing: error))")
            return
        }
        #expect(value > 1.09)
        // UIColor(red:...) takes extended-sRGB values; beyond the 0.002
        // tolerance they throw, within it they snap to the boundary.
        #expect(throws: ContrastError.self) {
            try SRGBColor(resolving: UIColor(red: 1.01, green: 0.5, blue: 0.5, alpha: 1),
                                      with: lightTraits)
        }
        #expect(try SRGBColor(resolving: UIColor(red: 1.001, green: 1, blue: 1, alpha: 1),
                                          with: lightTraits) == SRGBColor(red8: 255, green8: 255, blue8: 255))
    }

    @Test("Grayscale colors convert")
    func grayscale() throws {
        let white = try SRGBColor(resolving: UIColor(white: 1, alpha: 1), with: lightTraits)
        #expect(white == SRGBColor(red8: 255, green8: 255, blue8: 255))
        let black = try SRGBColor(resolving: UIColor(white: 0, alpha: 0.5), with: lightTraits)
        #expect(black == (try SRGBColor(red: 0, green: 0, blue: 0, alpha: 0.5)))
        // UIColor(white:) is gray with the sRGB transfer function, so 0.5 stays 0.5.
        let mid = try SRGBColor(resolving: UIColor(white: 0.5, alpha: 1), with: lightTraits)
        #expect(abs(mid.red - 0.5) < 1e-6)
        #expect(mid.red == mid.green && mid.green == mid.blue)
    }

    @Test("System colors resolve per trait collection")
    func systemColors() throws {
        let lightLabel = try SRGBColor(resolving: .label, with: lightTraits)
        let darkLabel = try SRGBColor(resolving: .label, with: darkTraits)
        #expect(lightLabel.red < 0.1)
        #expect(darkLabel.red > 0.9)
    }

    @Test("Pattern colors throw unconvertibleColor")
    func patternThrows() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let error = thrownError {
            _ = try SRGBColor(resolving: UIColor(patternImage: image), with: lightTraits)
        } as? ContrastError
        guard case .unconvertibleColor? = error else {
            Issue.record("expected unconvertibleColor, got \(String(describing: error))")
            return
        }
    }

    @Test("End to end: a theme built from dynamic UIColors audits like the same theme in hex")
    func endToEndAudit() throws {
        let theme = try BridgeFixture.theme { light, dark, variant in
            try SRGBColor(resolving: dynamicColor(light: light, dark: dark),
                                      with: variant == "dark" ? darkTraits : lightTraits)
        }
        let bridged = theme.audit(level: .aa)
        let reference = BridgeFixture.hexTheme.audit(level: .aa)
        #expect(bridged.results == reference.results)
        #expect(bridged.failureDescription == reference.failureDescription)
        let failing = bridged.results.filter { $0.status == .failed }
        #expect(failing.map { "\($0.variant)/\($0.pair.foreground)" } == ["light/muted"])
    }
}
#endif
