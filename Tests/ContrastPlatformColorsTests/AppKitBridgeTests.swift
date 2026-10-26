#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import ContrastCore
import ContrastPlatformColors
import Testing

/// A dynamic NSColor that is `light` under Aqua and `dark` under Dark Aqua.
private func dynamicColor(light: SRGBColor, dark: SRGBColor) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = isDark ? dark : light
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private func appearance(_ name: NSAppearance.Name) throws -> NSAppearance {
    try #require(NSAppearance(named: name))
}

@Suite("NSColor bridge")
struct AppKitBridgeTests {
    static let light = try? SRGBColor(red: 0.1, green: 0.2, blue: 0.3)
    static let dark = try? SRGBColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.5)

    @Test("Static sRGB colors round-trip exactly under both appearances",
          arguments: [(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.123456789, 0.5, 0.987654321, 1.0),
                      (28.0 / 255, 118.0 / 255, 1e-9, 0.25)])
    func staticSRGBRoundTrips(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) throws {
        let expected = try SRGBColor(red: red, green: green, blue: blue, alpha: alpha)
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        // Exact, not approximate: sRGB input skips ColorSync (see Conversion.swift).
        #expect(try SRGBColor(resolving: color, appearance: appearance(.aqua)) == expected)
        #expect(try SRGBColor(resolving: color, appearance: appearance(.darkAqua)) == expected)
    }

    @Test("A dynamic color resolves to the right value per appearance, in either order")
    func dynamicColorPerAppearance() throws {
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let color = dynamicColor(light: light, dark: dark)
        for name in [NSAppearance.Name.aqua, .darkAqua, .darkAqua, .aqua, .darkAqua] {
            let resolved = try SRGBColor(resolving: color, appearance: appearance(name))
            #expect(resolved == (name == .darkAqua ? dark : light), "\(name.rawValue)")
        }
    }

    @Test("The thread's current drawing appearance is ignored and then restored")
    func ambientAppearanceIgnored() throws {
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let color = dynamicColor(light: light, dark: dark)
        let aqua = try appearance(.aqua)
        let darkAqua = try appearance(.darkAqua)
        let before = NSAppearance.currentDrawing().name

        var results: [(ambient: NSAppearance.Name, resolved: SRGBColor, after: NSAppearance.Name)] = []
        var thrown: (any Error)?
        for (ambient, requested) in [(darkAqua, aqua), (aqua, darkAqua)] {
            ambient.performAsCurrentDrawingAppearance {
                do {
                    let resolved = try SRGBColor(resolving: color, appearance: requested)
                    results.append((ambient.name, resolved, NSAppearance.currentDrawing().name))
                } catch {
                    thrown = error
                }
            }
        }
        #expect(thrown == nil)
        #expect(results.map(\.resolved) == [light, dark])
        // Inside each block the ambient appearance is back in place after the call.
        #expect(results.map(\.after) == results.map(\.ambient))
        #expect(NSAppearance.currentDrawing().name == before)
    }

    @Test("Concurrent calls with different appearances do not interfere")
    func concurrentResolution() async throws {
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let outcomes = await withTaskGroup(of: (Bool, SRGBColor?).self) { group in
            for index in 0..<200 {
                group.addTask {
                    let wantsDark = index % 2 == 1
                    guard let requested = NSAppearance(named: wantsDark ? .darkAqua : .aqua) else {
                        return (wantsDark, nil)
                    }
                    let color = dynamicColor(light: light, dark: dark)
                    return (wantsDark, try? SRGBColor(resolving: color, appearance: requested))
                }
            }
            var collected: [(Bool, SRGBColor?)] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }
        #expect(outcomes.count == 200)
        for (wantsDark, resolved) in outcomes {
            #expect(resolved == (wantsDark ? dark : light))
        }
    }

    @Test("Alpha is kept, also when it differs per appearance")
    func alphaKept() throws {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.3)
        #expect(try SRGBColor(resolving: color, appearance: appearance(.aqua)).alpha == 0.3)
        let light = try #require(Self.light)
        let dark = try #require(Self.dark)
        let dynamic = dynamicColor(light: light, dark: dark)
        #expect(try SRGBColor(resolving: dynamic, appearance: appearance(.aqua)).alpha == 1)
        #expect(try SRGBColor(resolving: dynamic, appearance: appearance(.darkAqua)).alpha == 0.5)
    }

    @Test("Display P3 colors inside sRGB convert to the expected sRGB values",
          arguments: [[0.5, 0.3, 0.2], [0.8, 0.6, 0.4], [0.35, 0.55, 0.75], [0.9, 0.2, 0.15], [1, 1, 1]])
    func displayP3InGamut(_ p3: [Double]) throws {
        let expected = DisplayP3Reference.sRGB(fromDisplayP3: p3)
        #expect(expected.allSatisfy { (0...1).contains($0) }, "fixture must be inside sRGB")
        let color = NSColor(displayP3Red: p3[0], green: p3[1], blue: p3[2], alpha: 0.75)
        let resolved = try SRGBColor(resolving: color, appearance: appearance(.aqua))
        // ColorSync's Display P3 profile stores its matrix in ICC fixed point;
        // against the exact matrix it differed by up to 0.00064 per component
        // on a 0.05 grid, so 0.001 is the tolerance here.
        for (actual, wanted) in zip([resolved.red, resolved.green, resolved.blue], expected) {
            #expect(abs(actual - wanted) < 0.001, "\(actual) vs \(wanted)")
        }
        #expect(resolved.alpha == 0.75)
    }

    @Test("Display P3 colors outside sRGB throw componentOutOfRange instead of clamping")
    func displayP3OutOfGamut() throws {
        let aqua = try appearance(.aqua)
        let red = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let redError = thrownError {
            _ = try SRGBColor(resolving: red, appearance: aqua)
        } as? ContrastError
        guard case let .componentOutOfRange(component, value)? = redError else {
            Issue.record("expected componentOutOfRange, got \(String(describing: redError))")
            return
        }
        #expect(component == "red")
        #expect(abs(value - DisplayP3Reference.sRGB(fromDisplayP3: [1, 0, 0])[0]) < 0.001)

        // Display P3 green is negative in sRGB red, the other side of the range.
        let green = NSColor(displayP3Red: 0, green: 1, blue: 0, alpha: 1)
        let greenError = thrownError {
            _ = try SRGBColor(resolving: green, appearance: aqua)
        } as? ContrastError
        guard case let .componentOutOfRange("red", negative)? = greenError else {
            Issue.record("expected componentOutOfRange for red, got \(String(describing: greenError))")
            return
        }
        #expect(negative < -0.5)
    }

    @Test("Extended-sRGB components beyond the tolerance throw; within it they snap to the boundary")
    func extendedSRGBTolerance() throws {
        let aqua = try appearance(.aqua)
        for components: [CGFloat] in [[1.01, 0.5, 0.5, 1], [0.5, -0.01, 0.5, 1], [0.5, 0.5, 1.0021, 1]] {
            let color = NSColor(colorSpace: .extendedSRGB, components: components, count: 4)
            #expect(throws: ContrastError.self) {
                try SRGBColor(resolving: color, appearance: aqua)
            }
        }
        let nearWhite = NSColor(colorSpace: .extendedSRGB, components: [1.001, 1.0000001, 1, 1], count: 4)
        #expect(try SRGBColor(resolving: nearWhite, appearance: aqua)
            == SRGBColor(red8: 255, green8: 255, blue8: 255))
        let nearBlack = NSColor(colorSpace: .extendedSRGB, components: [-0.001, 0, -1e-7, 1], count: 4)
        #expect(try SRGBColor(resolving: nearBlack, appearance: aqua)
            == SRGBColor(red8: 0, green8: 0, blue8: 0))
    }

    @Test("Grayscale colors convert, and conversion noise at white is absorbed")
    func grayscale() throws {
        let aqua = try appearance(.aqua)
        let linearGray = try #require(CGColorSpace(name: CGColorSpace.linearGray))
        let linear = NSColor(colorSpace: NSColorSpace(cgColorSpace: linearGray) ?? .genericGray,
                             components: [0.5, 1], count: 2)
        let resolved = try SRGBColor(resolving: linear, appearance: aqua)
        // Linear 0.5 encoded with the sRGB transfer function.
        let expected = DisplayP3Reference.encode(0.5)
        #expect(abs(resolved.red - expected) < 1e-6)
        #expect(resolved.red == resolved.green && resolved.green == resolved.blue)

        // ColorSync returns 1.0000001192 (one Float32 step above 1) for generic
        // gray white; the conversion tolerance moves it onto the boundary.
        let white = try SRGBColor(resolving: NSColor(genericGamma22White: 1, alpha: 1), appearance: aqua)
        #expect(white == SRGBColor(red8: 255, green8: 255, blue8: 255))
        let black = try SRGBColor(resolving: NSColor(genericGamma22White: 0, alpha: 1), appearance: aqua)
        #expect(black == SRGBColor(red8: 0, green8: 0, blue8: 0))
    }

    @Test("System catalog colors resolve per appearance")
    func systemColors() throws {
        // Only the relationship is asserted: the exact system values are
        // Apple's to change.
        let lightText = try SRGBColor(resolving: .textColor, appearance: appearance(.aqua))
        let darkText = try SRGBColor(resolving: .textColor, appearance: appearance(.darkAqua))
        #expect(try lightText.relativeLuminance() < 0.1)
        #expect(try darkText.relativeLuminance() > 0.9)
    }

    @Test("Pattern colors and catalog colors without components throw unconvertibleColor",
          arguments: ["pattern", "scrubber"])
    func unconvertibleThrows(_ kind: String) throws {
        // A pattern NSColor's cgColor would be opaque black; the bridge must
        // not return that. The scrubber background is a system catalog color
        // that has no RGB components.
        let color = kind == "pattern"
            ? NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2)))
            : NSColor.scrubberTexturedBackground
        let error = thrownError {
            _ = try SRGBColor(resolving: color, appearance: appearance(.aqua))
        } as? ContrastError
        guard case .unconvertibleColor? = error else {
            Issue.record("expected unconvertibleColor, got \(String(describing: error))")
            return
        }
    }

    @Test("End to end: a theme built from dynamic NSColors audits like the same theme in hex")
    func endToEndAudit() throws {
        let aqua = try appearance(.aqua)
        let darkAqua = try appearance(.darkAqua)
        let theme = try BridgeFixture.theme { light, dark, variant in
            try SRGBColor(resolving: dynamicColor(light: light, dark: dark),
                                      appearance: variant == "dark" ? darkAqua : aqua)
        }
        let bridged = theme.audit(level: .aa)
        let reference = BridgeFixture.hexTheme.audit(level: .aa)
        #expect(bridged.results == reference.results)
        #expect(bridged.failureDescription == reference.failureDescription)
        #expect(!bridged.passed)
        let failing = bridged.results.filter { $0.status == .failed }
        #expect(failing.map { "\($0.variant)/\($0.pair.foreground)" } == ["light/muted"])
    }
}
#endif
