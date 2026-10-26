// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContrastAudit",
    // ContrastAuditTesting, including the Swift Testing helper, builds at
    // these minimums with Xcode 27.1 (macOS, and the generic iOS, tvOS,
    // watchOS and visionOS simulators). Lower values were not evaluated.
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    products: [
        .library(name: "ContrastCore", targets: ["ContrastCore"]),
        // Add this one to test targets only; it links XCTest and Swift Testing.
        .library(name: "ContrastAuditTesting", targets: ["ContrastAuditTesting"]),
        // Optional bridges from NSColor, UIColor and SwiftUI Color. Every
        // platform import is behind #if canImport, so on Linux it has no
        // public API.
        .library(name: "ContrastPlatformColors", targets: ["ContrastPlatformColors"]),
    ],
    targets: [
        .target(name: "ContrastCore"),
        .target(name: "ContrastAuditTesting", dependencies: ["ContrastCore"]),
        .target(name: "ContrastPlatformColors", dependencies: ["ContrastCore"]),
        // The fixture is read through #filePath rather than Bundle.module, so
        // it is excluded from the target instead of declared as a resource.
        .testTarget(name: "ContrastCoreTests", dependencies: ["ContrastCore"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "ContrastAuditTestingTests",
                    dependencies: ["ContrastAuditTesting", "ContrastCore"]),
        .testTarget(name: "ContrastPlatformColorsTests",
                    dependencies: ["ContrastPlatformColors", "ContrastCore"]),
    ]
)
