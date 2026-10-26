import ContrastAuditTesting
import ContrastCore
import DemoThemes
import XCTest

final class OrchardXCTests: XCTestCase {
    func testOrchardMeetsAA() {
        ContrastAudit.assertPasses(Orchard.theme, level: .aa)
    }
}
