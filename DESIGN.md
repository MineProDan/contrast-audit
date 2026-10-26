# ContrastAudit design

This document describes the public API of ContrastAudit 0.1, the WCAG
sources it is built on, and the reasoning behind each behavior. Section 10
lists the choices where exact WCAG behavior and convenience pulled in
different directions.

## 1. Purpose and non-goals

ContrastAudit checks a whole color theme against WCAG 2.1 contrast
requirements from inside `swift test`. You declare the foreground/background
pairs your UI actually uses once, give each variant (light, dark, increased
contrast, or any mode you define) a palette of named colors, and call one
assertion. If anything fails, the test fails once, with a message that names
every failing pair and gives the measured ratio and the required ratio.

Terms used throughout:

- **Pair**: a foreground color name, a background color name and a role.
- **Variant**: a named palette, mapping color names to colors.
- **Check**: one pair evaluated in one variant. A theme with 6 pairs and
  3 variants runs 18 checks.

### What this library will not do

- Generate palettes, suggest replacement colors or "fix" a failing pair.
- Simulate color-vision deficiencies.
- Convert between color spaces. Input is sRGB; the optional platform bridges
  convert to sRGB using the platform's own APIs and nothing more.
- Implement APCA, WCAG 3 or any other contrast model.
- Audit rendered UI, screenshots, images, gradients or text over photos.
- Detect a pair's role from font size or weight. The caller states the role.
- Model anti-aliasing, text borders or halos.
- Claim that a passing audit means an app is accessible. A passing audit means
  that the declared pairs meet the declared ratios, and nothing more.

## 2. WCAG basis

Sources, fetched 2026-10-25:

- WCAG 2.1 Recommendation, version dated 6 May 2025:
  https://www.w3.org/TR/WCAG21/ (glossary: relative luminance, contrast ratio,
  large scale text; SC 1.4.3, 1.4.6, 1.4.11).
- Understanding SC 1.4.3:
  https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- Understanding SC 1.4.6:
  https://www.w3.org/WAI/WCAG21/Understanding/contrast-enhanced.html
- Understanding SC 1.4.11:
  https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
- WCAG2ICT Group Note, dated 11 December 2025: https://www.w3.org/TR/wcag2ict/

### 2.1 Relative luminance

For each sRGB channel `c` in 0...1, the linear value is `c / 12.92` when
`c <= 0.04045` and `((c + 0.055) / 1.055) ^ 2.4` otherwise. Then
`L = 0.2126 R + 0.7152 G + 0.0722 B`.

**Linearization constant.** The current WCAG 2.1 text uses 0.04045, the value
from the sRGB standard. A note in the glossary says the definition used 0.03928
before May 2021, that the old value came from an older version of the sRGB
specification, and that the change has no practical effect for these
guidelines. ContrastCore uses 0.04045. For 8-bit input the two constants
cannot disagree: 10/255 (about 0.0392) is below both and 11/255 (about 0.0431)
is above both, so every 8-bit channel value takes the same branch. A quick
test computes both for all 256 channel values and requires bit-identical
results. Non-8-bit inputs between the two constants (from the
Double initializer) use 0.04045.

### 2.2 Contrast ratio

`(L1 + 0.05) / (L2 + 0.05)`, where L1 is the lighter color's relative luminance
and L2 the darker's. The glossary notes that the range is 1 to 21. The ratio
is symmetric for opaque colors.

**Rounding.** All three Understanding documents say computed values
"should not be rounded" when compared with a threshold. Their examples are that
4.499:1 does not meet 4.5:1 and 2.999:1 does not meet 3:1. ContrastCore compares
unrounded values with `>=`.

**Background.** The glossary notes say contrast is measured against the
specified background, that white is assumed when none is specified, and that
specifying a text color without a background (or the reverse) is a failure.
ContrastCore requires both colors on every pair and never assumes white (see
section 5.3 and decision D5).

### 2.3 Thresholds

| Criterion | Level | Applies to | Ratio |
|---|---|---|---|
| 1.4.3 Contrast (Minimum) | AA | text and images of text | 4.5:1 |
| 1.4.3 Contrast (Minimum) | AA | large-scale text | 3:1 |
| 1.4.6 Contrast (Enhanced) | AAA | text and images of text | 7:1 |
| 1.4.6 Contrast (Enhanced) | AAA | large-scale text | 4.5:1 |
| 1.4.11 Non-text Contrast | AA | UI components and graphical objects | 3:1 against adjacent colors |

1.4.11 is Level AA, and none of the fetched pages mentions an AAA counterpart.
So `.uiComponent` requires 3:1 at both levels (decision D3). Each criterion has
exceptions (incidental text, logotypes, inactive components, essential
graphics). Those are a human judgment; the library's mechanism for them is a
waiver with a reason.

### 2.4 Large-scale text and points

WCAG defines large-scale text as at least 18 point, or at least 14 point bold,
or an equivalent size for CJK fonts. The Understanding documents for 1.4.3 and
1.4.6 give 1pt = 1.333px, so 14pt and 18pt are about 18.5px and 24px (CSS
pixels). The WCAG notes say the point size should come from the user agent or
be calculated the way a user agent does.

WCAG2ICT, for non-web software, adds two notes. One says that 1 point means
1.333 CSS pixels. The other says that non-web software does not use CSS
pixels and should use the platform's density-independent unit instead, and it
names points (pt) as that unit on iOS and macOS.

**What this settles and what it does not.** Read together, the two notes treat
one Apple point like one CSS pixel. On that reading, WCAG's 18pt corresponds to
about 24 Apple points and 14pt bold to about 18.7 Apple points bold. The 18 and
14 in WCAG are not Apple points. That is our inference from two notes. WCAG2ICT
gives no Apple-specific conversion and no worked example, and it is a Group
Note, not a Recommendation. It also does not address Dynamic Type, where the
rendered size depends on user settings. The library takes no position at
runtime: the caller chooses the role. The README recommends using
`.bodyText` unless the text is clearly large at the smallest size it can
render, and it will cite both notes.

WCAG 2.2 was not checked in this session, and nothing here relies on it.

## 3. Module layout

| Module | Imports | Purpose |
|---|---|---|
| `ContrastCore` | Foundation only | Colors, ratios, themes, audit, waivers, baseline, reports. Runs on macOS and Linux. |
| `ContrastAuditTesting` | ContrastCore; XCTest and Testing, each behind `#if canImport` | The two assertion helpers. Added only to test targets. |
| `ContrastPlatformColors` | ContrastCore; SwiftUI, UIKit, AppKit, CoreGraphics behind `#if canImport` | Optional bridges from `NSColor`, `UIColor` and SwiftUI `Color` to `SRGBColor` (section 9). No public API on Linux. |

ContrastCore never imports SwiftUI, UIKit, AppKit, XCTest or Testing. A CI step
greps `Sources/ContrastCore` for those imports.

**Imports for users.** ContrastAuditTesting uses `public import ContrastCore`,
written explicitly so the import is correct whether or not imports default to
internal. It does not re-export ContrastCore. A `public import` lets the
helpers' signatures use core types, but clients still need `import ContrastCore`
to name `Theme` and the other core types. The alternative, `@_exported import`,
is an underscored attribute with no stability promise, so users write two
imports (decision N9).

The manifest as shipped:

```swift
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
```

There are no third-party dependencies. `Examples/ThemeAuditDemo` is a separate
package that depends on this one by local path.

## 4. Public API

Every public type is a `Sendable` value type. None is publicly `Codable`. The
two JSON formats (baseline, report) go through explicit `json()` functions and
internal transfer types. That keeps the file formats independent of how the
Swift types are laid out, and it puts the schema-version check where decoding
cannot skip it. Errors use plain `throws` with the error type documented
(`ContrastError`). Typed throws would fix the error type permanently in the
API, and back-deployment behavior was not verified for every supported OS.

### 4.1 Types and why each exists

| Type | Why it earns its place |
|---|---|
| `SRGBColor` | The one color input type; validates components once. |
| `ContrastRatio` | Keeps the unrounded value and the one display rule (truncation) together, so no caller formats a ratio differently. |
| `PairRole` | WCAG thresholds depend on it, and it must be explicit per pair. |
| `ConformanceLevel` | AA vs AAA; one audit runs at one level. |
| `ColorPair` | Declares one foreground/background relationship once for all variants. |
| `Variant` | A named palette; supplies the colors, including backdrops, for one mode. |
| `Theme` | Pairs plus variants; the unit you audit. |
| `Waiver` | A documented exception, with a reason, that never counts as a pass. |
| `Baseline` (+ `Baseline.Entry`) | Known failures that may not get worse; lets an existing project adopt the package without a red build. |
| `AuditReport` | The result; all output formats come from it. |
| `CheckResult` (+ `Status`) | One check's outcome; inspectable without parsing strings. |
| `AuditProblem` | Configuration mistakes, reported as data instead of thrown, so one run reports everything. |
| `ContrastError` | Errors thrown by the direct APIs (parsing, luminance of a translucent color, baseline decoding). |
| `ContrastAudit` (testing module) | Namespace for the two assertion helpers. |

Deliberately not types: a backdrop (it is just a color name, see 5.3) and a
pair name (a pair is identified by its two color names, see 5.1).

### 4.2 ContrastCore

```swift
/// An sRGB color with gamma-encoded components in 0...1 and alpha in 0...1.
/// Hashable so that tests can compare parsed colors.
public struct SRGBColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Creates a color from components in 0...1.
    /// - Throws: `ContrastError.componentOutOfRange` if any component is
    ///   non-finite or outside 0...1. Values are never clamped, because a
    ///   value of 1.02 usually means an extended-range color that this package
    ///   cannot audit correctly.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) throws

    /// Creates a color from 8-bit components. Cannot fail. The distinct labels
    /// keep integer literals unambiguous: `SRGBColor(red: 28, ...)` always
    /// selects the Double initializer, which then throws for 28 instead of
    /// silently reading it as 28/255.
    public init(red8: UInt8, green8: UInt8, blue8: UInt8, alpha8: UInt8 = 255)

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` (CSS order, alpha
    /// last). The `#` is optional and digits are case-insensitive. `#RGB`
    /// expands each digit (`#1AF` is `#11AAFF`). `AARRGGBB` (alpha first) is
    /// not supported. An 8-digit string is always read as RRGGBBAA, so
    /// alpha-first input cannot be detected; convert it before passing it in.
    /// - Throws: `ContrastError.malformedHex` for empty input, any other
    ///   length, non-hex characters, whitespace or a `0x` prefix.
    public init(hex: String) throws

    /// True when alpha is exactly 1.
    public var isOpaque: Bool { get }

    /// Source-over compositing of `self` on `background`, applied to
    /// gamma-encoded components (the W3C Compositing and Blending formula,
    /// see 5.3). Cannot fail. Compositing in linear light gives different
    /// results and is not offered (decision D4).
    public func composited(over background: SRGBColor) -> SRGBColor

    /// WCAG 2.1 relative luminance (threshold 0.04045).
    /// - Throws: `ContrastError.translucentColor` when alpha < 1, because the
    ///   luminance of a translucent color depends on what is behind it.
    public func relativeLuminance() throws -> Double
}

/// A WCAG contrast ratio, 1...21. Stores the unrounded value; there is no
/// public initializer from a raw Double, so every ratio a caller sees was
/// computed by this library or is a WCAG requirement.
public struct ContrastRatio: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The unrounded ratio. All comparisons use this value.
    public let value: Double

    /// Computes the ratio for a foreground drawn on a background. A
    /// translucent foreground is composited over the background. A
    /// translucent background is first composited over `backdrop`.
    /// - Throws: `ContrastError.missingBackdrop` if the background is
    ///   translucent and `backdrop` is nil; `ContrastError.translucentBackdrop`
    ///   if the backdrop is translucent.
    public init(foreground: SRGBColor, background: SRGBColor, backdrop: SRGBColor? = nil) throws

    /// Truncated to two decimals, never rounded up: 4.499... prints "4.49:1".
    /// Locale-independent.
    public var description: String { get }

    /// `value >= role.requiredRatio(at: level).value`, unrounded.
    public func meets(_ role: PairRole, at level: ConformanceLevel) -> Bool
}

/// What a pair is, which decides its WCAG requirement. No default.
public enum PairRole: String, Sendable, CaseIterable {
    /// Text below the large-scale size (SC 1.4.3 / 1.4.6).
    case bodyText
    /// At least 18pt, or at least 14pt bold, in WCAG's units (see DESIGN 2.4).
    case largeText
    /// UI components and graphical objects (SC 1.4.11). 3:1 at AA and AAA.
    case uiComponent

    /// AA: 4.5 / 3 / 3. AAA: 7 / 4.5 / 3.
    public func requiredRatio(at level: ConformanceLevel) -> ContrastRatio
}

public enum ConformanceLevel: String, Sendable, CaseIterable {
    case aa = "AA"
    case aaa = "AAA"
}

/// A foreground/background relationship, declared once per theme and
/// checked in every variant. Identified by (foreground, background).
public struct ColorPair: Sendable, Hashable {
    public let foreground: String
    public let background: String
    public let role: PairRole
    /// Name of an opaque palette color behind a translucent background.
    /// Looked up only in variants where the background is translucent.
    public let backdrop: String?
    /// Free text shown in Markdown and JSON reports.
    public let note: String?

    public init(_ foreground: String, on background: String, role: PairRole,
                backdrop: String? = nil, note: String? = nil)
}

/// A named palette. Duplicate or malformed entries never trap; they are
/// reported by the audit.
public struct Variant: Sendable {
    public let name: String

    /// `KeyValuePairs` instead of `Dictionary`: a dictionary literal with a
    /// duplicate key traps at runtime, while this reports it.
    public init(_ name: String, colors: KeyValuePairs<String, SRGBColor>)

    /// Hex strings are parsed during the audit; a malformed one becomes an
    /// `AuditProblem.malformedColor` instead of an error at declaration, so
    /// a theme can be declared without `try` and every typo is reported in
    /// one run.
    public init(_ name: String, hex: KeyValuePairs<String, String>)

    /// For palettes built in a loop (for example from a token enum).
    public init(_ name: String, entries: [(name: String, color: SRGBColor)])
}

public struct Theme: Sendable {
    public let name: String
    public let pairs: [ColorPair]
    public let variants: [Variant]

    public init(_ name: String, pairs: [ColorPair], variants: [Variant])

    /// Runs every check. Never throws and never traps: configuration
    /// problems become `AuditProblem`s and fail the report.
    public func audit(level: ConformanceLevel, waivers: [Waiver] = [],
                      baseline: Baseline? = nil) -> AuditReport
}

/// A reviewed exception. Applies to failing checks only; never turns a check
/// into a pass and never hides an invalid check.
public struct Waiver: Sendable, Hashable {
    public let foreground: String
    public let background: String
    /// nil means every variant.
    public let variant: String?
    public let reason: String
    /// Free text such as "remove after the 2.0 redesign". Not a Date, so
    /// results do not depend on the clock.
    public let expiryNote: String?

    public init(_ foreground: String, on background: String, variant: String?,
                reason: String, expiryNote: String? = nil)
}

/// Known failures recorded at one level. See section 5.5.
public struct Baseline: Sendable, Equatable {
    public static let currentSchemaVersion: Int  // 1
    /// Ratios within this distance of the recorded value count as unchanged.
    public static let tolerance: Double          // 1e-6

    public struct Entry: Sendable, Hashable {
        public let variant: String
        public let foreground: String
        public let background: String
        /// Unrounded ratio at recording time.
        public let ratio: Double
    }

    public let level: ConformanceLevel
    /// Sorted by variant, foreground, background, so diffs stay small.
    public let entries: [Entry]

    /// Records every check whose status is failed, knownFailure or regressed,
    /// at its current ratio. Waived and invalid checks are not recorded.
    public init(recording report: AuditReport)

    /// - Throws: `ContrastError.unsupportedBaselineVersion` for any
    ///   schemaVersion other than 1; `ContrastError.malformedBaseline` for
    ///   invalid JSON, missing fields, an unknown level, duplicate entries,
    ///   or a ratio that is non-finite or outside 1...21.
    public init(json: String) throws

    /// Pretty-printed, sorted keys, trailing newline.
    public func json() -> String
}

public struct AuditReport: Sendable {
    public let themeName: String
    public let level: ConformanceLevel
    /// Variant declaration order, then pair declaration order.
    public let results: [CheckResult]
    /// Theme-level problems, in the order found.
    public let problems: [AuditProblem]
    /// Waivers that matched no failing check.
    public let unusedWaivers: [Waiver]
    /// Baseline entries whose check now passes, is waived, improved beyond
    /// the tolerance, or no longer exists. Re-record to tighten the baseline.
    public let outdatedBaselineEntries: [Baseline.Entry]

    /// False if any check failed, regressed or is invalid, or if `problems`
    /// is not empty. Unused waivers and outdated entries do not fail.
    public var passed: Bool { get }
    /// One line of counts, always present.
    public var summary: String { get }
    /// The aggregated message (section 6.1), or nil when `passed`.
    public var failureDescription: String? { get }
    public func markdown() -> String
    public func json() -> String
}

public struct CheckResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case passed
        case failed
        case waived(Waiver)
        case knownFailure(baseline: ContrastRatio)
        case regressed(baseline: ContrastRatio)
        case invalid(AuditProblem)
    }
    public let variant: String
    public let pair: ColorPair
    public let required: ContrastRatio
    /// nil only when the status is `.invalid`.
    public let ratio: ContrastRatio?
    public let status: Status
}

/// A configuration mistake. Theme-level cases appear in
/// `AuditReport.problems`; check-level cases in `Status.invalid`.
public enum AuditProblem: Sendable, Equatable, CustomStringConvertible {
    // Theme level
    case noPairs
    case noVariants
    case duplicateVariant(String)
    case duplicatePair(foreground: String, background: String)
    case duplicateColorName(variant: String, name: String)
    case malformedColor(variant: String, name: String, input: String)
    case baselineLevelMismatch(baseline: ConformanceLevel, audit: ConformanceLevel)
    // Check level
    case missingColor(String)
    case unusableColor(String)   // malformed or duplicated in this palette
    case missingBackdrop(background: String, alpha: Double)
    case unknownBackdrop(String)
    case translucentBackdrop(String, alpha: Double)
}

public enum ContrastError: Error, Sendable, Equatable, CustomStringConvertible {
    case malformedHex(String)
    case componentOutOfRange(component: String, value: Double)
    case translucentColor(alpha: Double)
    case missingBackdrop
    case translucentBackdrop(alpha: Double)
    case malformedBaseline(String)
    case unsupportedBaselineVersion(Int)
    case unconvertibleColor(String)   // ContrastPlatformColors only
}
```

### 4.3 ContrastAuditTesting

```swift
public import ContrastCore

/// Namespace for the assertion helpers.
public enum ContrastAudit {}

#if canImport(XCTest)
import XCTest
extension ContrastAudit {
    /// Audits `theme` and, if the report did not pass, records exactly one
    /// XCTest failure containing `failureDescription`, attributed to the
    /// caller's file and line. Returns the report so that callers can attach
    /// `markdown()` or inspect results.
    @discardableResult
    public static func assertPasses(_ theme: Theme, level: ConformanceLevel,
                                    waivers: [Waiver] = [], baseline: Baseline? = nil,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) -> AuditReport
}
#endif

#if canImport(Testing)
public import Testing
extension ContrastAudit {
    /// Swift Testing equivalent: records exactly one `Issue` with the
    /// aggregated message at the caller's source location.
    @discardableResult
    public static func expectPasses(_ theme: Theme, level: ConformanceLevel,
                                    waivers: [Waiver] = [], baseline: Baseline? = nil,
                                    sourceLocation: SourceLocation = #_sourceLocation)
                                    -> AuditReport
}
#endif
```

Two names instead of one overloaded name: `assertPasses` mirrors `XCTAssert`,
and `expectPasses` mirrors `#expect`. With both frameworks importable in one
file, distinct names mean the reader always knows which framework records the
failure. `#_sourceLocation` is the documented default for Swift Testing helper
functions, and the helper tests check that failures are attributed to the
caller's line. Neither
helper prints. On success they do nothing, even when there are unused waivers
or outdated baseline entries; those appear in the returned report.

## 5. Describing a theme

### 5.1 Pairs and identity

A theme lists its pairs once. A pair names colors; it never holds them. A check
is identified by (variant, foreground, background), so the message reads
`[dark] 'subtitle' on 'card'`. Declaring the same (foreground, background)
twice is a theme problem; the first declaration is used and later ones are
skipped. If one color pair serves two roles (for example, an accent used both
for text and for an icon on the same surface), declare it once with the
stricter role (decision D9).

### 5.2 Variants

Every variant must supply every color that a pair refers to. A missing name
makes that check invalid ("no color named 'banner' in this variant"). It does
not crash and does not skip the check silently. Unreferenced palette entries
are allowed, so one palette can serve several themes. Duplicate variant names
are a theme problem; only the first is audited.

v0.1 limitation: every pair is checked in every variant. A pair that exists in
only some variants (for example a surface that only dark mode uses) must go in
a separate theme. Per-variant pair lists can be added later without breaking
this API (decision D14).

### 5.3 Transparency and backdrops

Rules, applied per check:

1. Resolve the background. If it is opaque, use it. If not, the pair must name
   a `backdrop`, that name must exist in this variant's palette, and that color
   must be opaque. The background is composited over it. Each failure mode is
   its own invalid status. Nothing falls back to white.
2. Resolve the foreground. If it is translucent, composite it over the resolved
   background.
3. Compute the ratio of the two opaque results.

The backdrop is a name, not a color. That way each variant supplies its own
(for example, a light wallpaper in light mode and a dark one in dark mode). It
is looked up only when the background is translucent in that variant, because
pairs are shared and one variant may use an opaque card where another uses a
translucent one.

Compositing is source-over on gamma-encoded sRGB components:
`out = fg * a + bg * (1 - a)`, the simple alpha compositing formula of W3C
Compositing and Blending Level 1
(https://www.w3.org/TR/compositing-1/#simplealphacompositing) applied to the
encoded values. WCAG says nothing about transparency, and that spec does not
fix the color space, so this is a documented choice (decision D4).
Compositing in linear light would give different results and is not
offered.

### 5.4 Waivers

A waiver matches failing checks by foreground, background and variant (nil
means all variants). A matched check becomes `.waived(waiver)`: it is shown
with its ratio and reason, counted separately, and never counted as passed.
Waivers do not apply to invalid checks, because a misconfiguration is not a
contrast exception. A waiver that matches no failing check is listed in
`unusedWaivers` and in the message footer, but does not fail the audit. A
mistyped waiver cannot hide anything: the pair it meant to cover still fails
under its real name (decision D8).

A waiver ignores the ratio. A waived pair can get worse without failing. That
is intended for real exemptions (logotypes, inactive controls). For debt that
must not grow, use the baseline.

### 5.5 Baseline

A baseline is a recorded list of failing checks and their ratios, at one level.

| Check this run | Baseline entry | Status | Fails? |
|---|---|---|---|
| fails | none | `failed` | yes |
| fails, ratio >= recorded - tolerance | present | `knownFailure` | no |
| fails, ratio < recorded - tolerance | present | `regressed` | yes |
| fails, ratio > recorded + tolerance | present | `knownFailure`, entry listed as outdated | no |
| passes | present | `passed`, entry listed as outdated | no |
| not in theme | present | entry listed as outdated | no |
| invalid | any | `invalid` | yes |

Precedence for one check: invalid, then passed, then waiver, then baseline,
then failed. If a waiver and a baseline entry both match, the waiver wins and
the entry is listed as outdated. A waiver is a deliberate decision with a
reason, and the baseline only records the state of things.

If `baseline.level` differs from the audit level, the report gets
`baselineLevelMismatch`, the baseline is ignored, and the audit fails.
Silently comparing AA ratios against an AAA recording would be meaningless.

**Tolerance 1e-6.** The same Swift code can differ in the last bits between
Apple's and glibc's `pow`, a relative difference near 1e-16, which is far below
1e-6. The smallest real change, one step of one 8-bit channel, moves a ratio by
about 2e-5 or more (the smallest case is the blue channel near 0 when both
colors are light), which is above 1e-6. So the tolerance absorbs platform noise
but catches every one-step change to an 8-bit channel of an opaque color.
Smaller edits can fall inside it: for example, a one-step alpha change on a
translucent foreground whose color is close to its background. Because regressions can be smaller than the
0.01 display step, a regression line also prints the difference to six decimals.

**Workflow.**

1. Record: run the audit with your waivers, call `Baseline(recording:)`, write
   `json()` to a file next to the tests (example in 8.2, behind an environment
   variable so it never runs in CI).
2. Store: commit the file. It holds color names and ratios, never color values.
3. Use: load it with `Baseline(json:)` and pass it to the assertion.
4. Update: when the footer reports outdated entries, re-record to tighten the
   baseline. Re-recording after a regression accepts the regression. That is
   a visible change to a committed file, so it shows up in code review.

File format (version 1):

```json
{
  "entries" : [
    {
      "background" : "surface",
      "foreground" : "icon-outline",
      "ratio" : 2.7916390550241523,
      "variant" : "dark"
    }
  ],
  "level" : "AA",
  "schemaVersion" : 1
}
```

## 6. Output formats

### 6.1 Failure message

```
Contrast audit failed for theme '<theme>' at <level>: <k> of <n> checks failed (<p> pairs x <v> variants).
  [theme] <theme-level problem>
  [<variant>] '<fg>' on '<bg>'  <ratio>  needs <required> (<level>, <role>)
  [<variant>] '<fg>' on '<bg>'  <ratio>  needs <required> (<level>, <role>), regressed from baseline <old> (-<delta>)
  [<variant>] '<fg>' on '<bg>'  invalid: <reason>
Not counted as failures: <w> waived, <b> known failures (baseline).
Housekeeping: <u> unused waivers, <o> outdated baseline entries.
```

Rules: theme problems come first, then failing checks in declaration order.
`k` counts failed, regressed and invalid checks. When theme problems exist the
header says `<t> theme problems; <k> of <n> checks failed`. The last two lines
appear only when one of their counts is non-zero, and they name only the
non-zero counts (a run without a baseline never mentions one); singular and
plural forms are used correctly. Waived and known failures are counted but not listed, which
keeps CI logs short; the Markdown and JSON reports list them. Ratios and
requirements use `ContrastRatio.description`. When even black or white cannot
meet the requirement on the resolved background, the line adds
`; unreachable on this background, best possible <r>`. That flags AAA targets
which no foreground color can meet.

Example from the realistic theme in 8.2 (an exact-string test checks it):

```
Contrast audit failed for theme 'Harbor' at AA: 2 of 18 checks failed (6 pairs x 3 variants).
  [light] 'icon-outline' on 'surface'  2.30:1  needs 3.00:1 (AA, UI component)
  [dark] 'subtitle' on 'card'  3.26:1  needs 4.50:1 (AA, body text)
Not counted as failures: 1 waived, 1 known failure (baseline).
```

Other lines (same method):

```
  [dark] 'icon-outline' on 'surface'  2.47:1  needs 3.00:1 (AA, UI component), regressed from baseline 2.79:1 (-0.319989)
  [light] 'label' on 'chip'  4.24:1  needs 7.00:1 (AAA, body text); unreachable on this background, best possible 4.95:1
  [dark] 'link' on 'banner'  invalid: no color named 'banner' in this variant
  [dark] 'caption' on 'glass'  invalid: background 'glass' is translucent (alpha 0.60) and the pair has no backdrop
  [theme] baseline was recorded at AAA but this audit runs at AA
```

(`#4D5964` on `#111921` is 2.4716...; `#FFFFFF` on `#6D7E81` is 4.2410...,
and the best possible on that background is 4.9515...)

`summary` is always one line:
`Harbor at AA: 14 passed, 2 failed, 1 waived, 1 known failure, 0 regressed, 0 invalid.`

### 6.2 Truncated display

`description` prints the largest two-decimal number that, read back as a
Double, does not exceed the stored value. So the display never exceeds the
value, and a ratio stored as the double nearest 1.13 (which is 1.1299...)
prints "1.13".

A naive `floor(value * 100)` is wrong in both directions, because the
multiplication rounds: for some doubles just below a step it rounds up (and
would print one hundredth too high), and for some doubles that are the nearest
double to a step it lands just below the integer (and would print one
hundredth too low). The algorithm is `c = floor(value * 100)`, then
`if Double(c) / 100 > value { c -= 1 } else if Double(c + 1) / 100 <= value { c += 1 }`,
then integer formatting (`c / 100`, a dot, `c % 100` as two digits), so no
locale is involved.

An earlier version stepped only down, which printed the double nearest 1.13
as "1.12"; it was found by the tests below on 819 of 6,003 values. The rule is
defined against the stored double, not against exact rational truncation,
because the double nearest 1.13 should print "1.13".

Invariants tested: next to every two-decimal value from 1.00 to 21.00, the
display read back is at most the value and the next hundredth exceeds it; the
double nearest each step prints that step; and for each requirement R in
{3, 4.5, 7}, the 1,000 doubles below R display below R (for example
`4.5.nextDown` displays `4.49:1`). A failing ratio therefore never displays at
or above its requirement.

### 6.3 Markdown

```markdown
## Contrast audit: Harbor (AA)

Failed: 2 of 18 checks failed (6 pairs x 3 variants). 1 waived, 1 known failure.

| Variant | Foreground | Background | Role | Ratio | Required | Status |
|---|---|---|---|---|---|---|
| light | text | surface | body text | 14.42:1 | 4.50:1 | passed |
| light | icon-outline | surface | UI component | 2.30:1 | 3.00:1 | **failed** |
| dark | logo-text | badge | large text | 2.90:1 | 3.00:1 | waived: Logotype, exempt under 1.4.3 |
| dark | icon-outline | surface | UI component | 2.79:1 | 3.00:1 | known failure (baseline 2.79:1) |
```

A pair's note goes in a final column when any pair has one. Names and reasons
are escaped for `|` and newlines.

### 6.4 JSON

```json
{
  "level" : "AA",
  "outdatedBaselineEntries" : [],
  "passed" : false,
  "problems" : [],
  "results" : [
    {
      "background" : "surface",
      "foreground" : "icon-outline",
      "ratio" : 2.307640972413328,
      "required" : 3,
      "role" : "uiComponent",
      "status" : "failed",
      "variant" : "light"
    }
  ],
  "schemaVersion" : 1,
  "summary" : "Harbor at AA: 14 passed, 2 failed, 1 waived, 1 known failure, 0 regressed, 0 invalid.",
  "theme" : "Harbor",
  "unusedWaivers" : []
}
```

Keys are written in sorted order, as shown, by a hand-written writer, so the
same doubles always produce the same bytes. Status-specific fields are added
where they apply: `waiverReason`, `expiryNote`, `baselineRatio`, `problem`
(the problem's description), and `note` when the pair has one. An invalid
check writes `"ratio" : null`. Ratios are unrounded, and `pow` may differ in
the last bit between macOS and Linux, so the JSON can differ in the last
digits across platforms. Compare it for meaning, not byte for byte, across
platforms.

## 7. Error handling

| Situation | Where | Behavior |
|---|---|---|
| Malformed hex in `SRGBColor(hex:)` | direct API | throws `malformedHex(input)`; message lists accepted forms |
| Malformed hex in `Variant(_, hex:)` | audit | theme problem `malformedColor`; checks using it are `invalid(.unusableColor)` |
| Component out of range or non-finite | `SRGBColor(red:...)` | throws `componentOutOfRange`; no clamping |
| Luminance of a translucent color | direct API | throws `translucentColor` |
| Translucent background, no backdrop | `ContrastRatio(...)` / audit | throws `missingBackdrop` / `invalid(.missingBackdrop)` |
| Backdrop name not in palette | audit | `invalid(.unknownBackdrop)` |
| Translucent backdrop | `ContrastRatio(...)` / audit | throws `translucentBackdrop` / `invalid(.translucentBackdrop)` |
| Color name missing in a variant | audit | `invalid(.missingColor)` |
| Duplicate color name, pair or variant | audit | theme problem; first one wins for pairs and variants, the color becomes unusable |
| No pairs or no variants | audit | theme problem `noPairs` / `noVariants`; the audit fails |
| Baseline JSON malformed or wrong version | `Baseline(json:)` | throws; the caller's test fails at the `try` |
| Baseline level differs | audit | theme problem; baseline ignored |

An empty theme fails. Passing an audit that checked nothing would hide a
misconfiguration, such as a loop that built no pairs (decision D7).

Library code contains no force-unwraps, no `fatalError` and no `print`.

## 8. Usage examples

### 8.1 Hello audit (XCTest)

```swift
import XCTest
import ContrastCore
import ContrastAuditTesting

final class HelloContrastTests: XCTestCase {
    func testHelloTheme() {
        let theme = Theme("Hello",
            pairs: [ColorPair("text", on: "surface", role: .bodyText),
                    ColorPair("hint", on: "surface", role: .bodyText)],
            variants: [Variant("light", hex: ["text": "#1E2B37", "hint": "#8B959F", "surface": "#FFFFFF"])])
        ContrastAudit.assertPasses(theme, level: .aa)
    }
}
```

Fails with (ratios 14.42 and 3.04):

```
Contrast audit failed for theme 'Hello' at AA: 1 of 2 checks failed (2 pairs x 1 variant).
  [light] 'hint' on 'surface'  3.04:1  needs 4.50:1 (AA, body text)
```

### 8.2 Realistic theme (Swift Testing)

Three variants, a translucent surface on a per-variant backdrop, one waiver
and a baseline. All names and values are invented.

```swift
import Foundation
import Testing
import ContrastCore
import ContrastAuditTesting

enum Harbor {
    static let pairs = [
        ColorPair("text", on: "surface", role: .bodyText),
        ColorPair("subtitle", on: "card", role: .bodyText),
        ColorPair("link", on: "surface", role: .bodyText),
        ColorPair("icon-outline", on: "surface", role: .uiComponent),
        // "glass" is translucent; it sits on the variant's own wallpaper.
        ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper"),
        ColorPair("logo-text", on: "badge", role: .largeText, note: "Wordmark"),
    ]

    static let theme = Theme("Harbor", pairs: pairs, variants: [
        Variant("light", hex: [
            "text": "#1E2B37", "subtitle": "#5A6B7C", "surface": "#FFFFFF",
            "card": "#F1F3F6", "link": "#1D6BAE", "icon-outline": "#A1ACB7",
            "glass": "#FFFFFFB3", "wallpaper": "#476CA3", "caption": "#2A3B4D",
            "badge": "#C9561A", "logo-text": "#FFFFFF",
        ]),
        Variant("dark", hex: [
            "text": "#E9EEF1", "subtitle": "#697887", "surface": "#111921",
            "card": "#1D2934", "link": "#69B1EC", "icon-outline": "#54616D",
            "glass": "#11192199", "wallpaper": "#476CA3", "caption": "#D3D9DE",
            "badge": "#E37D27", "logo-text": "#FFFFFF",
        ]),
        Variant("increased-contrast", hex: [
            "text": "#000000", "subtitle": "#292E33", "surface": "#FFFFFF",
            "card": "#F6F6F6", "link": "#0A4D89", "icon-outline": "#4B535E",
            "glass": "#FFFFFFE6", "wallpaper": "#476CA3", "caption": "#000000",
            "badge": "#9E3F06", "logo-text": "#FFFFFF",
        ]),
    ])

    static let waivers = [
        Waiver("logo-text", on: "badge", variant: nil,
               reason: "Logotype, exempt under 1.4.3",
               expiryNote: "Revisit if the wordmark changes"),
    ]

    // #filePath keeps this working on Linux, where Bundle.module resources
    // would need extra setup.
    static let baselineURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("harbor-baseline.json")
}

@Suite struct HarborContrastTests {
    @Test func harborMeetsAA() throws {
        let baseline = try Baseline(json: String(contentsOf: Harbor.baselineURL, encoding: .utf8))
        ContrastAudit.expectPasses(Harbor.theme, level: .aa,
                                   waivers: Harbor.waivers, baseline: baseline)
    }

    // RECORD_CONTRAST_BASELINE=1 swift test --filter recordHarborBaseline
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECORD_CONTRAST_BASELINE"] == "1"))
    func recordHarborBaseline() throws {
        let report = Harbor.theme.audit(level: .aa, waivers: Harbor.waivers)
        try Baseline(recording: report).json()
            .write(to: Harbor.baselineURL, atomically: true, encoding: .utf8)
    }
}
```

Computed results at AA: 14 passes; `logo-text` on `badge` in dark (2.90) is
waived; `icon-outline` on `surface` in dark (2.79) is in the baseline; light
`icon-outline` (2.30) and dark `subtitle` on `card` (3.26) fail, which produces
the message in 6.1. In light mode, `glass` (#FFFFFF at alpha 0.70) over
`wallpaper` composites to about (200.2, 211.2, 227.6) in 8-bit terms, and
`caption` on it measures 7.59:1.

The same assertion in XCTest is
`ContrastAudit.assertPasses(Harbor.theme, level: .aa, waivers: Harbor.waivers, baseline: baseline)`.
The recording test there starts with
`try XCTSkipUnless(ProcessInfo.processInfo.environment["RECORD_CONTRAST_BASELINE"] == "1")`.

## 9. ContrastPlatformColors

A separate library product, so that projects that describe
themes in hex never link it. Every bridge sits behind `#if canImport(...)`; on
Linux the module has no public API. Measurements below were made with Xcode 27.1
(Swift 6.4) on macOS 26.6 arm64 and the iOS 27.0 simulator.

### 9.1 API

Three initializers on `SRGBColor`, each taking the appearance explicitly:

```swift
// macOS 11+, any thread. Not on Mac Catalyst.
public init(resolving color: NSColor, appearance: NSAppearance) throws
// iOS 13+, tvOS 13+, visionOS; any thread. Not on watchOS (no resolvedColor(with:)).
public init(resolving color: UIColor, with traitCollection: UITraitCollection) throws
// macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS; main actor.
@MainActor public init(resolving color: Color, in environment: EnvironmentValues) throws
```

The package minimums are unchanged; the AppKit and SwiftUI initializers carry
`@available` instead. One core addition: `ContrastError.unconvertibleColor(String)`
for colors with no single sRGB value.

**Name clash, resolved by renaming.** The core color type was first named
`RGBColor`. On macOS, `import AppKit` (and therefore `import SwiftUI`) exposes
QuickDraw's C struct `RGBColor` (`QD.framework/Headers/Quickdraw.h`), so in a
file that imported AppKit or SwiftUI and ContrastCore, `RGBColor` used as a
type failed with "'RGBColor' is ambiguous for type lookup". Reproduced in a
separate package with `func use(_ c: RGBColor)` and `[String: RGBColor]`;
plain expressions happened to compile. The type was renamed to `SRGBColor`
before the first release, a name that appears in no header or swiftinterface of
the macOS, iOS, tvOS, watchOS or visionOS SDKs in Xcode 27.1. A test in
`ContrastPlatformColorsTests` uses `SRGBColor` unqualified in type positions
next to `import AppKit` and `import SwiftUI`, so a future clash fails the
build.

### 9.2 How each bridge avoids the current environment

- **AppKit**: the conversion runs inside
  `appearance.performAsCurrentDrawingAppearance { }`, the non-deprecated API
  since macOS 11 (`NSAppearance.current`'s setter was deprecated in macOS 12;
  see `NSAppearance.h`). The header documents the drawing appearance as
  per-thread and the call as saving and restoring the previous one. Inside
  it, `usingType(.componentBased)` resolves dynamic and catalog colors. Tests
  resolve under one appearance while another is current, check that the
  ambient appearance is back afterwards, and run 200 concurrent resolutions in
  alternating appearances. No main-actor requirement.
- **UIKit**: `resolvedColor(with:)` against the given trait collection only.
  Tests resolve inside `performAsCurrent` of the opposite style. Runs on any
  thread (the tests run on Swift Testing's cooperative pool).
- **SwiftUI**: `Color.resolve(in:)` with the given `EnvironmentValues`
  (`EnvironmentValues()` starts as `.light`, which a test checks). The
  initializer is `@MainActor`: for a color backed by a platform color
  (`Color(nsColor:)`, `Color(uiColor:)`), SwiftUI hops synchronously to the
  main thread (`Update.syncMain`, seen in a stack sample). Called off the main
  thread under `swift test`, where no app services that hop, it hung forever.
  On the main actor it returns immediately.

### 9.3 Conversion rules

1. The result is gamma-encoded sRGB with alpha kept and full `Double`
   precision; nothing is quantized to 8 bits.
2. A CGColor already in sRGB or extended sRGB is read without conversion, so
   `NSColor(srgbRed:...)` and `UIColor(red:...)` round-trip exactly. Any other
   space is converted with `CGColor.converted(to: extendedSRGB, intent:
   .relativeColorimetric)`. Extended sRGB is unbounded, so wide-gamut colors
   come out with components outside 0...1 instead of being mapped into gamut.
3. **No clamping.** A component outside 0...1 by more than the tolerance
   throws `componentOutOfRange` (from the core initializer). Display P3 red is
   red 1.093, green -0.227 in sRGB; clamping it would audit a different color
   from the one on screen (on a wide-gamut display), so the caller decides:
   audit an sRGB fallback, or waive the pair.
4. **Tolerance 0.002.** Bridged components within 0.002 of 0...1 are moved onto
   the boundary; values inside 0...1 are never changed. It applies to every
   bridged value, because the platform may convert before the bridge sees the
   color: on iOS, `UIColor(displayP3Red: 1, green: 1, blue: 1, alpha: 1)` already
   yields an extended-sRGB CGColor with green 1.0000001192. Observed noise
   (9.4) reaches 0.0012 outside the range, so a tighter bound would reject
   in-gamut colors. 0.002 is about half of one 8-bit step, so a snapped color
   is indistinguishable from the boundary at 8-bit precision. Alpha is never
   converted and gets no tolerance.
5. A pattern color, a catalog color without components (for example
   `NSColor.scrubberTexturedBackground`), a color space without a CoreGraphics
   equivalent, or a failed conversion throws `unconvertibleColor`. The AppKit
   bridge checks this before touching `cgColor`, because `cgColor` of a pattern
   `NSColor` silently returns opaque black.
6. **SwiftUI components.** Per the SwiftUICore documentation in the Xcode 27.1
   SDK (`SwiftUICore.swiftdoc`), `Color.Resolved` stores its values "in the
   Linear sRGB color space, using extended range" as `Float`. `linearRed` and
   friends are those linear values; `red`, `green`, `blue` are the
   gamma-encoded sRGB values. The bridge reads `red`, `green`, `blue` and
   `opacity`. Availability from the SDK interface: `Color.resolve(in:)` and
   `Color.Resolved` are iOS 17, macOS 14, tvOS 17, watchOS 10.

### 9.4 Measurements

| Path | Observation |
|---|---|
| ColorSync, sRGB to extended sRGB (identity) | max error 2.8e-8 (Float32), hence the no-conversion path |
| ColorSync, white from generic gray, Lab, calibrated RGB | 1.0000001192 (one Float32 step above 1) |
| ColorSync, Display P3 vs exact matrix (0.05 grid) | max 0.00064 per component; ICC profiles store matrices in fixed point |
| ColorSync, sRGB colors expressed in Display P3, 200,000 random | up to 0.00063 outside 0...1 |
| SwiftUI, sRGB colors | max error 2.8e-8 (Float storage) |
| SwiftUI, Display P3 white | red 1.0000879, green 0.99996, blue 0.99982 |
| SwiftUI, Display P3 vs exact, 200,000 random | max 0.0029 per component; up to 0.00077 outside 0...1 |
| SwiftUI, sRGB boundary colors via ColorSync's P3 | up to 0.0012 outside 0...1 |

The exact reference is the matrix derived from the published sRGB and Display
P3 chromaticities (test `Support.swift`). Because SwiftUI's own Display P3
conversion is the least precise, the `NSColor` and `UIColor` bridges are the
better choice for Display P3 colors.

### 9.5 Tests and limits

`Tests/ContrastPlatformColorsTests`, Swift Testing. macOS (`swift test`): 12
NSColor tests and 7 SwiftUI tests. iOS 27.0 simulator (`xcodebuild test`): 9
UIColor tests and the same 7 SwiftUI tests. They cover exact sRGB round
trips, dynamic colors in both orders, ignoring the ambient appearance or
traits, alpha, in-gamut Display P3 against the independent reference,
out-of-gamut Display P3 throwing, the tolerance at both edges, grayscale,
system colors, pattern colors throwing, and an end-to-end audit whose results
equal those of the same theme declared in hex.

Not tested: Linux (no Linux toolchain or container here; the module has no
public API there by construction), running on tvOS, watchOS, visionOS and Mac Catalyst (all four
compile, including the tests, but were not run; on watchOS the SwiftUI
dynamic-color test has no portable dynamic color and would fail its
`#require`), asset catalog colors (no catalog in the package), on-device
rendering, and how a wide-gamut display actually shows a color.

## 10. Design decisions

Where exact WCAG behavior and convenience differ, or where WCAG is silent:

- **D1 Linearization constant**: 0.04045 (the current WCAG 2.1 text). A test
  checks that 0.03928 gives the same result for all 256 8-bit values.
- **D2 Comparison and display**: ratios are compared unrounded with `>=`
  (WCAG-exact) and displayed truncated to two decimals (6.2).
- **D3 Non-text at AAA**: `.uiComponent` stays 3:1 at AAA, because 1.4.11 is
  AA-only. The alternative would be to mark those checks "not applicable".
- **D4 Compositing**: the source-over formula of W3C Compositing and Blending
  Level 1 (https://www.w3.org/TR/compositing-1/#simplealphacompositing),
  applied to gamma-encoded sRGB components. WCAG is silent on transparency,
  and that spec does not settle the color space, so this is a documented
  choice. Linear-light compositing is not offered.
- **D5 No assumed white**: WCAG assumes white when no background is
  specified; this package requires an explicit opaque backdrop for
  translucent backgrounds instead.
- **D6 Large text**: the caller chooses the role. The README explains the
  WCAG2ICT reading (about 24 Apple pt regular, 18.7 pt bold) as an
  interpretation.
- **D7 Empty theme fails**, so a misconfigured theme cannot pass vacuously.
- **D8 Unused waivers** are reported in the returned report, not failed.
- **D9 Pair identity** is (variant, foreground, background), not including
  role; duplicates are a theme problem.
- **D10 Waiver vs baseline**: the waiver wins and ignores the ratio; the
  baseline is a ratchet with tolerance 1e-6.
- **D11 Strict components**: no clamping in the Double initializer.
- **D12 Unreachable hint** in failure lines (best possible ratio).
- **D13 Output**: waived and known failures are counted, not listed, in the
  failure message.
- **D14 Pairs apply to every variant**; variant-specific pairs go in a
  separate theme.

Naming and API shape:

- **N1** `SRGBColor` (see section 9 for why it is not `RGBColor`), with a
  throwing `init(red:green:blue:alpha:)` and a non-throwing `init(red8:...)`.
- **N2** `PairRole` with `.bodyText`, `.largeText`, `.uiComponent`.
- **N3** `CheckResult` and the word "check" in messages.
- **N4** `AuditProblem` (one enum for theme- and check-level problems) and
  `ContrastError`.
- **N5** `ContrastAudit.assertPasses` (XCTest) and `ContrastAudit.expectPasses`
  (Swift Testing).
- **N6** `level:` is required on the helpers, with no default.
- **N7** `Waiver(..., variant:)` has no default, so "all variants" is written
  as `nil`.
- **N8** `Variant` takes `colors:`, `hex:` and `entries:`.
- **N9** Two imports (`ContrastCore` + `ContrastAuditTesting`); no
  `@_exported`. There is no module named `ContrastAudit`.
- **N10** No public `Codable`; JSON goes through `json()` and
  `Baseline(json:)`.

## 11. Testing plan

ContrastCore (Swift Testing, plus a few XCTest cases where needed):

- Reference vectors: black/white = 21 exactly, any color on itself = 1,
  `#767676` on white = 4.5422... (passes 4.5), `#777777` on white =
  4.4780... (fails 4.5).
- Linearization: 0.03928 and 0.04045 give bit-identical results for all
  256 8-bit values.
- Boundaries: `ContrastRatio` at exactly 3, 4.5 and 7 passes; `nextDown`
  fails and displays below the requirement; the truncation invariant holds on a
  table of values next to every two-decimal value.
- Properties: symmetry for opaque pairs, range 1...21, monotonicity (a gray
  ramp 0...255 against black never decreases, and against white never
  increases).
- Requirements table: every (role, level) combination.
- Alpha: foreground compositing, background over backdrop, both translucent,
  alpha 0 and 1, missing, unknown and translucent backdrops, luminance of a
  translucent color throwing, a backdrop ignored for an opaque background.
- Hex: every accepted form, case, optional `#`; rejects empty, lengths 1, 2,
  5, 7 and 9, `0x`, whitespace, non-hex and non-ASCII digits.
- Components: NaN, infinity, negative, above 1 all throw.
- Audit: declaration order, missing color, duplicate pair, color and variant,
  empty theme, malformed palette hex.
- Waivers: per variant and all variants, unused, never applied to invalid
  checks, never counted as passes.
- Baseline: each row of the table in 5.5, tolerance edges (plus and minus
  2e-6 and 0.5e-6), level mismatch, JSON round-trip, version 2 rejected,
  malformed and duplicate entries, sorted output.
- Failure-path messages: `failureDescription`, `summary`, `markdown()` and
  `json()` compared as exact strings against expected literals for the
  Hello and Harbor themes. These are plain string tests in the core, so they
  run on Linux.

ContrastAuditTesting:

- On Apple platforms (`#if canImport(Darwin)`), `XCTExpectFailure` around
  `assertPasses` on the failing Harbor theme checks that exactly one failure
  is recorded, with exactly the expected message. `withKnownIssue` with a
  `matching:` closure does the same for `expectPasses`. Only the XCTest ones
  are guarded, because `withKnownIssue` is part of open-source Swift Testing
  and Linux CI can run those. Passing themes record nothing.

Independent cross-check:

- `scripts/verify_vectors.py` (stdlib only, run with `python3 -I`)
  recomputes luminance, compositing and ratios independently from section 2. It
  generates at least 100 pairs (all 256 grays against black and against white,
  seeded random opaque pairs, translucent pairs with backdrops) into a JSON
  fixture. A Swift test compares against it with a relative tolerance of 1e-9.
  The script's `--check` mode regenerates the fixture and fails on any
  difference.
