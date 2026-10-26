import ContrastCore
import Foundation
import Testing

// Compares ContrastCore with the independent Python implementation in
// scripts/verify_vectors.py, through the fixture it generates.
//
// The fixture is found through #filePath rather than Bundle.module: it works
// the same on macOS and Linux whenever tests run from the source tree (which
// `swift test` always does), and it avoids depending on where each toolchain
// places resource bundles next to the test binary.

@Suite("Independent reference vectors")
struct ReferenceVectorTests {
    struct Fixture: Decodable {
        let seed: Int
        let cases: [Case]
    }

    struct Case: Decodable {
        let kind: String
        let foreground: String
        let background: String
        let backdrop: String?
        let ratio: Double
    }

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("vectors.json")

    @Test("Every case matches the Python implementation within 1e-9 relative")
    func matchesPython() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        #expect(fixture.cases.count >= 100)

        var kinds: [String: Int] = [:]
        for (index, item) in fixture.cases.enumerated() {
            kinds[item.kind, default: 0] += 1
            let backdrop = try item.backdrop.map { try SRGBColor(hex: $0) }
            let ratio = try ContrastRatio(foreground: SRGBColor(hex: item.foreground),
                                          background: SRGBColor(hex: item.background),
                                          backdrop: backdrop)
            let relative = abs(ratio.value - item.ratio) / item.ratio
            #expect(relative <= 1e-9,
                    "case \(index) (\(item.kind)): \(item.foreground) on \(item.background) over \(item.backdrop ?? "-"): Swift \(ratio.value), Python \(item.ratio)")
        }
        // Each family from the generator is present.
        for kind in ["reference", "gray-on-black", "gray-on-white", "random-opaque",
                     "translucent-foreground", "translucent-background", "both-translucent"] {
            #expect(kinds[kind, default: 0] > 0, "no \(kind) cases in the fixture")
        }
        #expect(kinds["gray-on-black"] == 256)
        #expect(kinds["gray-on-white"] == 256)
    }
}
