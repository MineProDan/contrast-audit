import ContrastAuditTesting
import ContrastCore
import DemoThemes
import Foundation
import Testing

@Suite struct ThemeContrastTests {
    @Test func orchardMeetsAA() {
        ContrastAudit.expectPasses(Orchard.theme, level: .aa)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DEMO_SHOW_FAILURE"] == "1"))
    func emberMeetsAA() {
        // Ember fails on purpose, to show the failure output. It runs only
        // when asked (DEMO_SHOW_FAILURE=1 swift test), so `swift test` in this
        // package stays green. This comment sits inside the body because
        // Swift Testing prints comments placed directly above @Test along with
        // any failure.
        ContrastAudit.expectPasses(Ember.theme, level: .aa, waivers: Ember.waivers)
    }
}
