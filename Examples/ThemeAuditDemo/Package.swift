// swift-tools-version: 6.0
import PackageDescription

// A separate package that uses ContrastAudit the way an app would: the themes
// live in a regular target that depends only on ContrastCore, and only the
// test target links ContrastAuditTesting.
let package = Package(
    name: "ThemeAuditDemo",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    dependencies: [
        // The repository root. The explicit name keeps the product references
        // below working whatever the checkout folder is called (a clone is
        // usually named contrast-audit). An app would use
        // .package(url:from:) instead.
        .package(name: "ContrastAudit", path: "../.."),
    ],
    targets: [
        .target(name: "DemoThemes",
                dependencies: [.product(name: "ContrastCore", package: "ContrastAudit")]),
        .testTarget(name: "DemoThemesTests",
                    dependencies: ["DemoThemes",
                                   .product(name: "ContrastCore", package: "ContrastAudit"),
                                   .product(name: "ContrastAuditTesting", package: "ContrastAudit")]),
    ]
)
