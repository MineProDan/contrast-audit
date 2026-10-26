#if canImport(SwiftUI)
import ContrastCore
import ContrastPlatformColors
import SwiftUI
import Testing
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// Color.Resolved stores Float, so a Double input comes back with Float
// precision: observed error up to 2.8e-8 for sRGB colors. 1e-6 leaves margin
// while still catching any real conversion mistake (a linear/gamma mix-up is
// off by more than 0.1 for mid tones).
private let floatTolerance = 1e-6

private func expectClose(_ color: SRGBColor, _ expected: [Double], within tolerance: Double,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    let actual = [color.red, color.green, color.blue, color.alpha]
    for (value, wanted) in zip(actual, expected) {
        #expect(abs(value - wanted) <= tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }
}

/// A SwiftUI color that is `light` in the light color scheme and `dark` in
/// the dark one. SwiftUI has no portable dynamic-color initializer, so it
/// wraps the platform's dynamic color; SwiftUI resolves it from the
/// environment's colorScheme.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
private func dynamicColor(light: [Double], dark: [Double]) -> Color? {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
    })
    #elseif canImport(UIKit) && !os(watchOS)
    return Color(uiColor: UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c[0], green: c[1], blue: c[2], alpha: c[3])
    })
    #else
    return nil
    #endif
}

private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    return environment
}

// Main actor because the bridge is (see SwiftUIBridge.swift): off the main
// thread, resolving the platform-backed dynamic color below hangs under
// `swift test`.
@MainActor
@Suite("SwiftUI Color bridge")
struct SwiftUIBridgeTests {
    static let light = [0.1, 0.2, 0.3, 1.0]
    static let dark = [0.9, 0.8, 0.7, 0.5]

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("Static sRGB colors round-trip within Float precision",
          arguments: [[0.0, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0, 1.0], [0.123456789, 0.5, 0.987654321, 1.0],
                      [28.0 / 255, 118.0 / 255, 0.001, 0.25]])
    func staticSRGBRoundTrips(_ components: [Double]) throws {
        let color = Color(.sRGB, red: components[0], green: components[1], blue: components[2],
                          opacity: components[3])
        for scheme in [ColorScheme.light, .dark] {
            let resolved = try SRGBColor(resolving: color, in: environment(scheme))
            expectClose(resolved, components, within: floatTolerance)
        }
        // Black and white are exact, not merely close.
        let white = try SRGBColor(resolving: Color(.sRGB, red: 1, green: 1, blue: 1), in: EnvironmentValues())
        #expect(white == SRGBColor(red8: 255, green8: 255, blue8: 255))
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("A dynamic color resolves per colorScheme, in either order, and alpha is kept")
    func dynamicColorPerScheme() throws {
        let color = try #require(dynamicColor(light: Self.light, dark: Self.dark))
        for scheme in [ColorScheme.light, .dark, .dark, .light, .dark] {
            let resolved = try SRGBColor(resolving: color, in: environment(scheme))
            expectClose(resolved, scheme == .dark ? Self.dark : Self.light, within: floatTolerance)
        }
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("A default EnvironmentValues resolves the light scheme")
    func defaultEnvironmentIsLight() throws {
        let color = try #require(dynamicColor(light: Self.light, dark: Self.dark))
        #expect(EnvironmentValues().colorScheme == .light)
        expectClose(try SRGBColor(resolving: color, in: EnvironmentValues()), Self.light,
                    within: floatTolerance)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("Display P3 colors inside sRGB convert close to the exact sRGB values",
          arguments: [[0.5, 0.3, 0.2], [0.8, 0.6, 0.4], [0.35, 0.55, 0.75], [0.9, 0.2, 0.15]])
    func displayP3InGamut(_ p3: [Double]) throws {
        let color = Color(.displayP3, red: p3[0], green: p3[1], blue: p3[2], opacity: 1)
        let resolved = try SRGBColor(resolving: color, in: EnvironmentValues())
        // SwiftUI's own Display P3 conversion was measured up to 0.0029 per
        // component away from the exact result (200,000 random colors), so
        // the tolerance is 0.005.
        expectClose(resolved, DisplayP3Reference.sRGB(fromDisplayP3: p3) + [1], within: 0.005)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("Display P3 white does not throw: SwiftUI's overshoot is absorbed")
    func displayP3White() throws {
        // SwiftUI resolves Display P3 white to red 1.0000879 (observed), which
        // the conversion tolerance moves onto the boundary.
        let color = Color(.displayP3, red: 1, green: 1, blue: 1, opacity: 1)
        let resolved = try SRGBColor(resolving: color, in: EnvironmentValues())
        expectClose(resolved, [1, 1, 1, 1], within: 0.005)
        #expect(resolved.red <= 1)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("Display P3 colors outside sRGB throw componentOutOfRange")
    func displayP3OutOfGamut() throws {
        let color = Color(.displayP3, red: 1, green: 0, blue: 0, opacity: 1)
        let error = thrownError {
            _ = try SRGBColor(resolving: color, in: EnvironmentValues())
        } as? ContrastError
        guard case let .componentOutOfRange("red", value)? = error else {
            Issue.record("expected componentOutOfRange for red, got \(String(describing: error))")
            return
        }
        #expect(value > 1.09)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    @Test("End to end: a theme built from dynamic SwiftUI colors gives the same verdicts as hex")
    func endToEndAudit() throws {
        let theme = try BridgeFixture.theme { light, dark, variant in
            let toArray = { (c: SRGBColor) in [c.red, c.green, c.blue, c.alpha] }
            let color = try #require(dynamicColor(light: toArray(light), dark: toArray(dark)))
            return try SRGBColor(resolving: color, in: environment(variant == "dark" ? .dark : .light))
        }
        let bridged = theme.audit(level: .aa)
        let reference = BridgeFixture.hexTheme.audit(level: .aa)
        // Float storage changes ratios in the last digits, so compare the
        // verdicts and the ratios to 1e-4 rather than exactly.
        #expect(bridged.results.map(\.status) == reference.results.map(\.status))
        for (b, r) in zip(bridged.results, reference.results) {
            #expect(abs((b.ratio?.value ?? 0) - (r.ratio?.value ?? 0)) < 1e-4)
        }
        #expect(bridged.failureDescription == reference.failureDescription)
    }
}
#endif
