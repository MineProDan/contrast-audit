import ContrastCore
import Testing

@Suite("Hex parsing")
struct HexParsingTests {
    static let accepted: [(String, SRGBColor)] = [
        ("#1AF", SRGBColor(red8: 0x11, green8: 0xAA, blue8: 0xFF)),
        ("1AF", SRGBColor(red8: 0x11, green8: 0xAA, blue8: 0xFF)),
        ("#1af", SRGBColor(red8: 0x11, green8: 0xAA, blue8: 0xFF)),
        ("#1AF8", SRGBColor(red8: 0x11, green8: 0xAA, blue8: 0xFF, alpha8: 0x88)),
        ("1af8", SRGBColor(red8: 0x11, green8: 0xAA, blue8: 0xFF, alpha8: 0x88)),
        ("#12ABEF", SRGBColor(red8: 0x12, green8: 0xAB, blue8: 0xEF)),
        ("12abef", SRGBColor(red8: 0x12, green8: 0xAB, blue8: 0xEF)),
        ("#12aBeF", SRGBColor(red8: 0x12, green8: 0xAB, blue8: 0xEF)),
        ("#12ABEF80", SRGBColor(red8: 0x12, green8: 0xAB, blue8: 0xEF, alpha8: 0x80)),
        ("12abef80", SRGBColor(red8: 0x12, green8: 0xAB, blue8: 0xEF, alpha8: 0x80)),
        ("#000000", SRGBColor(red8: 0, green8: 0, blue8: 0)),
        ("#FFFFFFFF", SRGBColor(red8: 255, green8: 255, blue8: 255)),
        ("#00000000", SRGBColor(red8: 0, green8: 0, blue8: 0, alpha8: 0)),
    ]

    @Test("Accepted forms", arguments: accepted)
    func acceptsForm(_ input: String, _ expected: SRGBColor) throws {
        #expect(try SRGBColor(hex: input) == expected)
    }

    @Test("Alpha comes last and defaults to opaque")
    func alphaOrder() throws {
        let color = try SRGBColor(hex: "#11223344")
        #expect(color.red == Double(0x11) / 255)
        #expect(color.green == Double(0x22) / 255)
        #expect(color.blue == Double(0x33) / 255)
        #expect(color.alpha == Double(0x44) / 255)
        #expect(try SRGBColor(hex: "#112233").alpha == 1)
        #expect(try SRGBColor(hex: "#112233").isOpaque)
        #expect(try !SRGBColor(hex: "#112233FE").isOpaque)
    }

    static let rejected = [
        "", "#", "F", "#F", "FF", "#FF", "#FFFFF", "#FFFFFFF", "#FFFFFFFFF", "#FFFFFFFFFF",
        "0xFFFFFF", "0xFFF", "#0xFFF",
        " #FFFFFF", "#FFFFFF ", "#FF FFFF", "#FFFFFF\n", "\t#FFF",
        "#GGGGGG", "#12345Z", "##FFF", "#FF-FFF", "#+FFFFF",
        "#\u{0663}\u{0663}\u{0663}",       // Arabic-Indic digits
        "#\u{FF11}\u{FF12}\u{FF13}",       // full-width digits
        "#\u{FF21}\u{FF22}\u{FF23}",       // full-width letters
    ]

    @Test("Rejected input keeps the original string in the error", arguments: rejected)
    func rejects(_ input: String) {
        #expect(throws: ContrastError.malformedHex(input)) {
            try SRGBColor(hex: input)
        }
    }

    @Test("Malformed hex message lists the accepted forms")
    func malformedMessage() {
        #expect(ContrastError.malformedHex("#12").description
            == "malformed hex color '#12'; expected #RGB, #RGBA, #RRGGBB or #RRGGBBAA (the # is optional, alpha comes last)")
    }
}

@Suite("Components")
struct ComponentTests {
    @Test("Valid components are stored unchanged")
    func validComponents() throws {
        let color = try SRGBColor(red: 0, green: 0.25, blue: 1, alpha: 0.5)
        #expect(color.red == 0 && color.green == 0.25 && color.blue == 1 && color.alpha == 0.5)
        #expect(try SRGBColor(red: 0.1, green: 0.2, blue: 0.3).alpha == 1)
    }

    static let invalid: [(Double, Double, Double, Double, String)] = [
        (.nan, 0, 0, 1, "red"),
        (0, .infinity, 0, 1, "green"),
        (0, 0, -.infinity, 1, "blue"),
        (0, 0, 0, .nan, "alpha"),
        (-0.001, 0, 0, 1, "red"),
        (0, 1.02, 0, 1, "green"),
        (0, 0, 28, 1, "blue"),
        (0, 0, 0, 1.5, "alpha"),
        (0, 0, 0, -1, "alpha"),
    ]

    @Test("NaN, infinity, negative and above 1 throw without clamping", arguments: invalid)
    func rejectsComponent(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double,
                          _ expectedName: String) {
        let error = thrownError { _ = try SRGBColor(red: red, green: green, blue: blue, alpha: alpha) }
        guard case let .componentOutOfRange(component, value)? = error as? ContrastError else {
            Issue.record("expected componentOutOfRange, got \(String(describing: error))")
            return
        }
        #expect(component == expectedName)
        let inputs: [String: Double] = ["red": red, "green": green, "blue": blue, "alpha": alpha]
        let input: Double = inputs[expectedName] ?? 0
        let reportsInput: Bool = value.isNaN ? input.isNaN : value == input
        #expect(reportsInput)
    }

    @Test("8-bit initializer divides by 255")
    func eightBit() {
        let color = SRGBColor(red8: 0, green8: 51, blue8: 255, alpha8: 102)
        #expect(color.red == 0)
        #expect(color.green == 51.0 / 255)
        #expect(color.blue == 1)
        #expect(color.alpha == 102.0 / 255)
    }
}

@Suite("Compositing and luminance")
struct CompositingTests {
    @Test("Source-over on an opaque background mixes gamma-encoded components")
    func overOpaque() throws {
        let half = try SRGBColor(red: 1, green: 1, blue: 1, alpha: 0.5)
        let black = SRGBColor(red8: 0, green8: 0, blue8: 0)
        let mixed = half.composited(over: black)
        #expect(mixed == (try SRGBColor(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(mixed.alpha == 1)
    }

    @Test("Alpha 0 gives the background and alpha 1 the foreground")
    func alphaEdges() throws {
        let background = try hex("#336699")
        #expect(try hex("#FF000000").composited(over: background) == background)
        #expect(try hex("#FF0000").composited(over: background) == (try hex("#FF0000")))
    }

    @Test("Translucent over translucent uses Porter-Duff source-over")
    func overTranslucent() throws {
        let red = try SRGBColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        let blue = try SRGBColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let mixed = red.composited(over: blue)
        #expect(mixed.alpha == 0.75)
        #expect(abs(mixed.red - 2.0 / 3) < 1e-15)
        #expect(mixed.green == 0)
        #expect(abs(mixed.blue - 1.0 / 3) < 1e-15)

        let clear = try SRGBColor(red: 1, green: 1, blue: 1, alpha: 0)
        #expect(clear.composited(over: clear).alpha == 0)
    }

    @Test("Luminance of black is 0 and of white is 1")
    func luminanceEnds() throws {
        #expect(try hex("#000000").relativeLuminance() == 0)
        #expect(try hex("#FFFFFF").relativeLuminance() == 1)
    }

    @Test("Luminance of a translucent color throws")
    func translucentLuminance() throws {
        let color = try hex("#FFFFFF80")
        #expect(throws: ContrastError.translucentColor(alpha: 128.0 / 255)) {
            try color.relativeLuminance()
        }
        #expect(throws: ContrastError.translucentColor(alpha: 0)) {
            try hex("#FFFFFF00").relativeLuminance()
        }
    }
}
