// The core color type was first named RGBColor, which QuickDraw also defines
// and AppKit and SwiftUI expose on macOS. That made the name ambiguous in type
// positions. This file imports both frameworks and uses SRGBColor unqualified
// in type positions, so a new clash breaks the build rather than users' builds.
#if canImport(SwiftUI)
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif
import ContrastCore
import SwiftUI
import Testing

private func components(of color: SRGBColor) -> [Double] {
    [color.red, color.green, color.blue, color.alpha]
}

@Suite("Name clash")
struct NameClashTests {
    @Test("SRGBColor is unambiguous next to AppKit and SwiftUI")
    func unambiguousTypeName() throws {
        let palette: [String: SRGBColor] = ["ink": try SRGBColor(hex: "#203040")]
        let colors: [SRGBColor] = Array(palette.values)
        let expected: [Double] = [32.0 / 255, 48.0 / 255, 64.0 / 255, 1]
        let actual: [[Double]] = colors.map(components)
        #expect(actual == [expected])
    }
}
#endif
