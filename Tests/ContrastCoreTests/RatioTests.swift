// @testable gives access to two internals: ContrastRatio(uncheckedValue:),
// to build ratios at exact boundary values, and SRGBColor.linearize.
@testable import ContrastCore
import Foundation
import Testing

@Suite("Reference vectors")
struct ReferenceValueTests {
    @Test("Black on white is exactly 21 in both orders")
    func blackWhite() throws {
        #expect(try ContrastRatio(foreground: hex("#000000"), background: hex("#FFFFFF")).value == 21)
        #expect(try ContrastRatio(foreground: hex("#FFFFFF"), background: hex("#000000")).value == 21)
    }

    @Test("Any color on itself is exactly 1",
          arguments: ["#000000", "#FFFFFF", "#767676", "#1D6BAE", "#C9561A", "#010203"])
    func sameColor(_ text: String) throws {
        let color = try hex(text)
        #expect(try ContrastRatio(foreground: color, background: color).value == 1)
    }

    @Test("#767676 on white passes AA body text, about 4.5422")
    func gray767676() throws {
        let ratio = try ContrastRatio(foreground: hex("#767676"), background: hex("#FFFFFF"))
        #expect(abs(ratio.value - 4.5422) < 1e-4)
        #expect(ratio.meets(.bodyText, at: .aa))
        #expect(ratio.description == "4.54:1")
    }

    @Test("#777777 on white fails AA body text, about 4.4781")
    func gray777777() throws {
        let ratio = try ContrastRatio(foreground: hex("#777777"), background: hex("#FFFFFF"))
        #expect(abs(ratio.value - 4.4781) < 1e-4)
        #expect(!ratio.meets(.bodyText, at: .aa))
        #expect(ratio.description == "4.47:1")
    }

    /// The pre-2021 WCAG constant, written out here so that the library
    /// does not need to carry it.
    static func linearizeWithOldThreshold(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    @Test("Thresholds 0.03928 and 0.04045 agree bit for bit on all 256 8-bit values")
    func linearizationConstants() {
        for byte in 0...255 {
            let channel = Double(byte) / 255
            let current = SRGBColor.linearize(channel)
            let old = Self.linearizeWithOldThreshold(channel)
            #expect(current.bitPattern == old.bitPattern, "channel value \(byte)")
        }
    }
}

@Suite("Requirements and boundaries")
struct RequirementTests {
    static let table: [(PairRole, ConformanceLevel, Double)] = [
        (.bodyText, .aa, 4.5), (.largeText, .aa, 3), (.uiComponent, .aa, 3),
        (.bodyText, .aaa, 7), (.largeText, .aaa, 4.5), (.uiComponent, .aaa, 3),
    ]

    @Test("Requirement for every role and level", arguments: table)
    func requirement(_ role: PairRole, _ level: ConformanceLevel, _ expected: Double) {
        #expect(role.requiredRatio(at: level).value == expected)
    }

    @Test("The table covers every role and level")
    func tableIsComplete() {
        #expect(Self.table.count == PairRole.allCases.count * ConformanceLevel.allCases.count)
    }

    @Test("Exactly at the requirement passes; one ulp below fails and displays below it",
          arguments: [(3.0, "3.00:1", "2.99:1"), (4.5, "4.50:1", "4.49:1"), (7.0, "7.00:1", "6.99:1")])
    func boundary(_ value: Double, _ atText: String, _ belowText: String) {
        let exact = ContrastRatio(uncheckedValue: value)
        let below = ContrastRatio(uncheckedValue: value.nextDown)
        for role in PairRole.allCases {
            for level in ConformanceLevel.allCases where role.requiredRatio(at: level).value == value {
                #expect(exact.meets(role, at: level), "\(role) \(level)")
                #expect(!below.meets(role, at: level), "\(role) \(level)")
            }
        }
        #expect(exact.description == atText)
        #expect(below.description == belowText)
    }

    @Test("4.499 displays as 4.49:1, never 4.50:1")
    func noRoundingUp() {
        #expect(ContrastRatio(uncheckedValue: 4.499).description == "4.49:1")
        #expect(ContrastRatio(uncheckedValue: 4.4999999).description == "4.49:1")
        #expect(ContrastRatio(uncheckedValue: 2.999).description == "2.99:1")
        #expect(ContrastRatio(uncheckedValue: 21).description == "21.00:1")
        #expect(ContrastRatio(uncheckedValue: 1).description == "1.00:1")
        // Stored just below the decimal value, but it is the double for it.
        #expect(ContrastRatio(uncheckedValue: 1.13).description == "1.13:1")
        #expect(ContrastRatio(uncheckedValue: 1.17).description == "1.17:1")
    }

    static func text(_ hundredths: Int) -> String {
        let fraction = hundredths % 100
        return "\(hundredths / 100)." + (fraction < 10 ? "0" : "") + "\(fraction):1"
    }

    static func hundredths(of shown: String) -> Int {
        let digits = shown.dropLast(2).split(separator: ".")
        return (Int(digits[0]) ?? -1) * 100 + (Int(digits[1]) ?? -1)
    }

    @Test("Display never exceeds the value, next to every two-decimal value from 1.00 to 21.00")
    func truncationInvariant() {
        var checked = 0
        for hundredths in 100...2100 {
            let step = Double(hundredths) / 100
            for value in [step.nextDown, step, step.nextUp] {
                let shown = ContrastRatio(uncheckedValue: value).description
                let displayed = Self.hundredths(of: shown)
                // Read back as a double, the display never exceeds the value,
                // and it is the largest two-decimal number that does not.
                #expect(Double(displayed) / 100 <= value, "\(value) shows \(shown)")
                #expect(Double(displayed + 1) / 100 > value, "\(value) shows \(shown)")
                checked += 1
            }
            // The double nearest each step displays as that step.
            #expect(ContrastRatio(uncheckedValue: step).description == Self.text(hundredths), "\(step)")
            // The double just below each step displays below that step.
            #expect(Self.hundredths(of: ContrastRatio(uncheckedValue: step.nextDown).description) < hundredths,
                    "\(step.nextDown)")
        }
        #expect(checked == 6003)
    }

    @Test("At the three WCAG thresholds, a display at or above the threshold means the value meets it")
    func thresholdDisplay() {
        for threshold in [3.0, 4.5, 7.0] {
            let thresholdText = Self.text(Int(threshold * 100))
            var value = threshold
            for _ in 0..<1000 {
                value = value.nextDown
                #expect(ContrastRatio(uncheckedValue: value).description < thresholdText, "\(value)")
            }
            value = threshold
            for _ in 0..<1000 {
                #expect(ContrastRatio(uncheckedValue: value).description == thresholdText, "\(value)")
                value = value.nextUp
            }
        }
    }

    @Test("Comparable uses the unrounded value")
    func comparable() {
        let low = ContrastRatio(uncheckedValue: 4.5.nextDown)
        let high = ContrastRatio(uncheckedValue: 4.5)
        #expect(low < high)
        #expect(low != high)
        #expect(low.description != high.description)
    }
}

@Suite("Ratio properties")
struct RatioPropertyTests {
    /// A deterministic spread of opaque colors: every channel combination of
    /// six levels (216 colors).
    static let grid: [SRGBColor] = {
        let levels: [UInt8] = [0, 17, 51, 119, 204, 255]
        var colors: [SRGBColor] = []
        for red in levels {
            for green in levels {
                for blue in levels {
                    colors.append(SRGBColor(red8: red, green8: green, blue8: blue))
                }
            }
        }
        return colors
    }()

    @Test("Swapping foreground and background gives the same ratio, within 1...21")
    func symmetryAndRange() throws {
        for (index, first) in Self.grid.enumerated() {
            for second in Self.grid[index...] {
                let forward = try ContrastRatio(foreground: first, background: second).value
                let backward = try ContrastRatio(foreground: second, background: first).value
                #expect(forward == backward)
                #expect((1.0...21.0).contains(forward))
            }
        }
    }

    @Test("A gray ramp never loses contrast against black and never gains it against white")
    func monotonicity() throws {
        let black = SRGBColor(red8: 0, green8: 0, blue8: 0)
        let white = SRGBColor(red8: 255, green8: 255, blue8: 255)
        var previousOnBlack = 0.0
        var previousOnWhite = Double.infinity
        for level in UInt8.min...UInt8.max {
            let gray = SRGBColor(red8: level, green8: level, blue8: level)
            let onBlack = try ContrastRatio(foreground: gray, background: black).value
            let onWhite = try ContrastRatio(foreground: gray, background: white).value
            #expect(onBlack >= previousOnBlack, "gray \(level) on black")
            #expect(onWhite <= previousOnWhite, "gray \(level) on white")
            previousOnBlack = onBlack
            previousOnWhite = onWhite
        }
        #expect(previousOnBlack == 21)
        #expect(previousOnWhite == 1)
    }
}

@Suite("Ratio with transparency")
struct RatioAlphaTests {
    @Test("A translucent foreground is composited over the background")
    func translucentForeground() throws {
        let background = try hex("#FFFFFF")
        let foreground = try hex("#00000080")
        let ratio = try ContrastRatio(foreground: foreground, background: background)
        let manual = try ContrastRatio(foreground: foreground.composited(over: background), background: background)
        #expect(ratio == manual)
        #expect(ratio.value > 1 && ratio.value < 21)
    }

    @Test("A translucent background is composited over the backdrop")
    func translucentBackground() throws {
        let backdrop = try hex("#000000")
        let background = try hex("#FFFFFF80")
        let ratio = try ContrastRatio(foreground: hex("#000000"), background: background, backdrop: backdrop)
        let manual = try ContrastRatio(foreground: hex("#000000"), background: background.composited(over: backdrop))
        #expect(ratio == manual)
    }

    @Test("Both translucent: background over backdrop first, then foreground over the result")
    func bothTranslucent() throws {
        let backdrop = try hex("#476CA3")
        let background = try hex("#FFFFFFB3")
        let foreground = try hex("#2A3B4D99")
        let resolved = background.composited(over: backdrop)
        let ratio = try ContrastRatio(foreground: foreground, background: background, backdrop: backdrop)
        let manual = try ContrastRatio(foreground: foreground.composited(over: resolved), background: resolved)
        #expect(ratio == manual)
    }

    @Test("Background alpha 0 measures against the backdrop; alpha 1 ignores it")
    func backgroundAlphaEdges() throws {
        let clear = try ContrastRatio(foreground: hex("#000000"), background: hex("#12345600"),
                                      backdrop: hex("#FFFFFF"))
        #expect(clear.value == 21)
        let opaque = try ContrastRatio(foreground: hex("#000000"), background: hex("#FFFFFFFF"),
                                       backdrop: hex("#000000"))
        #expect(opaque.value == 21)
    }

    @Test("Foreground alpha 0 gives 1:1")
    func invisibleForeground() throws {
        #expect(try ContrastRatio(foreground: hex("#00000000"), background: hex("#FFFFFF")).value == 1)
    }

    @Test("A translucent background without a backdrop throws")
    func missingBackdrop() {
        #expect(throws: ContrastError.missingBackdrop) {
            try ContrastRatio(foreground: hex("#000000"), background: hex("#FFFFFF80"))
        }
    }

    @Test("A translucent backdrop throws")
    func translucentBackdrop() {
        #expect(throws: ContrastError.translucentBackdrop(alpha: 0x40 / 255.0)) {
            try ContrastRatio(foreground: hex("#000000"), background: hex("#FFFFFF80"),
                              backdrop: hex("#00000040"))
        }
    }

    @Test("The backdrop is ignored for an opaque background, even a translucent one")
    func backdropIgnored() throws {
        let ratio = try ContrastRatio(foreground: hex("#000000"), background: hex("#FFFFFF"),
                                      backdrop: hex("#FF000040"))
        #expect(ratio.value == 21)
    }
}
