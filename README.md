# ContrastAudit

A Swift package that checks a whole color theme against WCAG 2.1 contrast
requirements from inside `swift test`.

Themes that look fine on one screen often fail contrast in another mode, and a
per-pair ratio function only helps if someone remembers to call it for every
pair in every mode. ContrastAudit lets you declare the foreground/background
pairs your UI uses once, audit them across every variant (light, dark, or any
mode you define) with one assertion, and get a test failure that names each
failing pair with its measured and required ratio.

This is the Swift package. An unrelated TypeScript package with the same name
exists on npm ([registry entry](https://registry.npmjs.org/contrast-audit)).

## Hello audit

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

This test fails, attributed to the `assertPasses` line, with:

```
Contrast audit failed for theme 'Hello' at AA: 1 of 2 checks failed (2 pairs x 1 variant).
  [light] 'hint' on 'surface'  3.04:1  needs 4.50:1 (AA, body text)
```

Ratios are compared unrounded and printed truncated to two decimals, never
rounded up, so a ratio of 4.499 prints as `4.49:1`, never as `4.50:1` next to
a failure.

## Real output

The demo package in `Examples/ThemeAuditDemo` includes a theme that fails on
purpose. `DEMO_SHOW_FAILURE=1 swift test` in that folder printed the following
with Swift Testing (excerpt from `docs/example-output.txt`; build and passing
test lines removed):

```
✘ Test emberMeetsAA() recorded an issue at ThemeContrastTests.swift:19:35: Issue recorded
↳ Contrast audit failed for theme 'Ember' at AA: 2 of 12 checks failed (6 pairs x 2 variants).
    [light] 'toggle-track' on 'surface'  1.76:1  needs 3.00:1 (AA, UI component)
    [dark] 'subtitle' on 'surface'  3.89:1  needs 4.50:1 (AA, body text)
  Not counted as failures: 1 waived.
✘ Test emberMeetsAA() failed after 0.002 seconds with 1 issue.
✘ Suite ThemeContrastTests failed after 0.003 seconds with 1 issue.
✘ Test run with 2 tests in 1 suite failed after 0.003 seconds with 1 issue.
Note: Some test targets reported failures:
  - DemoThemesTests (Swift Testing)
```

The waived pair is counted but not listed, which keeps CI logs short. The
Markdown and JSON reports list every check.

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MineProDan/contrast-audit.git", from: "0.1.0"),
],
```

Then add the products to the targets that need them:

| Product | Add it to | What it contains |
|---|---|---|
| `ContrastCore` | Any target, including app code and test targets | Colors, ratios, themes, the audit, waivers, baselines and reports. Imports Foundation only. |
| `ContrastAuditTesting` | Test targets only | `ContrastAudit.assertPasses` (XCTest) and `ContrastAudit.expectPasses` (Swift Testing). Links XCTest and Swift Testing. |
| `ContrastPlatformColors` | Optional, where you need it | Bridges from `NSColor`, `UIColor` and SwiftUI `Color` to `SRGBColor`. No public API on Linux. |

```swift
.testTarget(name: "MyAppTests", dependencies: [
    .product(name: "ContrastCore", package: "contrast-audit"),
    .product(name: "ContrastAuditTesting", package: "contrast-audit"),
]),
```

Test files import both modules: `import ContrastCore` and
`import ContrastAuditTesting`. The testing module does not re-export the core.
There is no module named `ContrastAudit`; that is the package name and the
namespace of the two assertion helpers.

## Describing a theme

A theme is a list of pairs plus a list of variants. A pair names two colors
and a role; a variant maps color names to colors. Every pair is checked in
every variant, so a theme with 6 pairs and 3 variants runs 18 checks.

```swift
import ContrastCore

let theme = Theme("App", pairs: [
    ColorPair("text", on: "surface", role: .bodyText),
    ColorPair("icon", on: "surface", role: .uiComponent),
    ColorPair("caption", on: "glass", role: .bodyText, backdrop: "wallpaper"),
], variants: [
    Variant("light", hex: ["text": "#1E2B37", "icon": "#6B7785", "surface": "#FFFFFF",
                           "caption": "#1E2B37", "glass": "#FFFFFFB3", "wallpaper": "#476CA3"]),
    Variant("dark", hex: ["text": "#E9EEF1", "icon": "#8A96A3", "surface": "#111921",
                          "caption": "#E9EEF1", "glass": "#11192199", "wallpaper": "#476CA3"]),
])
```

Colors can be given as hex strings (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`,
alpha last) or as `SRGBColor` values (`Variant(_:colors:)`, or
`Variant(_:entries:)` for palettes built in a loop). A malformed hex string, a
missing color name or a duplicate name does not crash: it becomes a reported
problem and fails the audit, so one run lists every mistake. A theme with no
pairs or no variants also fails, because an audit that checked nothing would
hide a misconfiguration.

### Transparency and backdrops

Alpha is never ignored and white is never assumed. A translucent foreground is
composited over its background. A translucent background must name an opaque
`backdrop` color from the same variant (`backdrop: "wallpaper"` above), and it
is composited over that first. Each variant supplies its own backdrop color. If
the backdrop is missing, unknown or itself translucent, the check is reported
as invalid with the reason. Compositing uses the source-over formula of
[W3C Compositing and Blending Level 1](https://www.w3.org/TR/compositing-1/#simplealphacompositing)
on gamma-encoded sRGB components. WCAG itself does not define transparency, so
this is a documented choice ([DESIGN.md](DESIGN.md), decision D4).

### Waivers

A waiver is a reviewed exception with a reason, for example a logotype, which
SC 1.4.3 exempts:

```swift
let waivers = [
    Waiver("logo-text", on: "badge", variant: nil,   // nil: every variant
           reason: "Logotype, exempt under SC 1.4.3",
           expiryNote: "Revisit if the wordmark changes"),
]
ContrastAudit.assertPasses(theme, level: .aa, waivers: waivers)
```

A waived check is reported as waived, with its ratio and reason, and is never
counted as a pass. A waiver never hides an invalid check. A waiver that matches
nothing does not fail the audit; it is listed in the returned report's
`unusedWaivers` and in `markdown()`, and counted in the failure message when
the audit fails. A mistyped waiver cannot hide anything, because the pair it
meant to cover still fails under its real name.

### Baseline

A baseline lets an existing project adopt the audit without a red build on day
one. It records today's failures and their ratios at one level. Known failures
then pass, while new failures and any ratio that gets worse fail. Improvements
appear in the returned report's `outdatedBaselineEntries` and in `markdown()`,
so that you can tighten the baseline. The assertion helpers record nothing when
the audit passes.

1. Record it once, behind an environment variable so it never runs in CI:

   ```swift
   @Test(.enabled(if: ProcessInfo.processInfo.environment["RECORD_CONTRAST_BASELINE"] == "1"))
   func recordBaseline() throws {
       let report = theme.audit(level: .aa, waivers: waivers)
       try Baseline(recording: report).json()
           .write(to: baselineURL, atomically: true, encoding: .utf8)
   }
   ```

   ```sh
   RECORD_CONTRAST_BASELINE=1 swift test --filter recordBaseline
   ```

2. Commit the JSON file. It contains color names and ratios, never color
   values, and re-recording after a regression is a visible change in review.

3. Use it:

   ```swift
   @Test func themeMeetsAA() throws {
       let baseline = try Baseline(json: String(contentsOf: baselineURL, encoding: .utf8))
       ContrastAudit.expectPasses(theme, level: .aa, waivers: waivers, baseline: baseline)
   }
   ```

`baselineURL` can be built from `#filePath`, which also works on Linux. A
baseline recorded at one level and used at another fails the audit instead of
being compared. Ratios within 1e-6 of the recorded value count as unchanged,
which absorbs floating-point differences between platforms but not a one-step
change of an 8-bit channel of an opaque color. Smaller edits, such as a
one-step alpha change on a translucent color close to its background, can fall
inside it (see [DESIGN.md](DESIGN.md), section 5.5).

### Reports

`assertPasses` and `expectPasses` return the `AuditReport`. You can also call
`theme.audit(level:waivers:baseline:)` directly. The report has `passed`, a
one-line `summary`, the aggregated `failureDescription`, `markdown()` (a table
of every check) and `json()` (a versioned format with unrounded ratios), plus
`results` for inspecting individual checks in code.

## Roles and large text

Every pair states its role, and the role sets the requirement:

| Role | AA | AAA | WCAG 2.1 |
|---|---|---|---|
| `.bodyText` | 4.5:1 | 7:1 | SC 1.4.3, 1.4.6 |
| `.largeText` | 3:1 | 4.5:1 | SC 1.4.3, 1.4.6 |
| `.uiComponent` | 3:1 | 3:1 | SC 1.4.11 (Level AA only, so AAA uses 3:1 too) |

WCAG defines large-scale text as at least 18 point, or at least 14 point bold
([WCAG 2.1](https://www.w3.org/TR/WCAG21/),
[Understanding SC 1.4.3](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)).
Those are not Apple points. The [WCAG2ICT](https://www.w3.org/TR/wcag2ict/)
Group Note says that 1 point is 1.333 CSS pixels and that non-web software
should use the platform's density-independent unit in place of CSS pixels,
naming points on iOS and macOS. Our reading of the two notes together, which is
an interpretation rather than official guidance, is that large text means about
24 Apple points regular or about 18.7 Apple points bold. WCAG2ICT does not
address Dynamic Type. Use `.bodyText` unless the text is clearly large at the
smallest size it can render. The library never guesses a role from a font.

## Platform color bridges

`ContrastPlatformColors` converts platform colors to `SRGBColor`. A dynamic
color has no single value, so every bridge takes the appearance explicitly and
never resolves against the current environment:

```swift
import AppKit
import ContrastCore
import ContrastPlatformColors

let dark = try #require(NSAppearance(named: .darkAqua))
let label = try SRGBColor(resolving: .labelColor, appearance: dark)
```

| Initializer | Availability |
|---|---|
| `SRGBColor(resolving: NSColor, appearance: NSAppearance)` | macOS 11 and later, any thread. Not on Mac Catalyst. |
| `SRGBColor(resolving: UIColor, with: UITraitCollection)` | iOS, tvOS and visionOS, any thread. Not on watchOS. |
| `SRGBColor(resolving: Color, in: EnvironmentValues)` | macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1 and later. Main actor. |

Colors are converted to sRGB with the platform's APIs. Nothing is clamped: a
wide-gamut color outside sRGB (for example Display P3 red) throws
`componentOutOfRange`, so you decide whether to audit an sRGB fallback or waive
the pair. Only measured converter noise within 0.002 of the 0...1 range is
moved onto the boundary. Pattern colors and other colors without a single sRGB
value throw `unconvertibleColor`. The bridges were tested on macOS and in the
iOS simulator; tvOS, watchOS, visionOS and Mac Catalyst were built but not run.
Details are in [DESIGN.md](DESIGN.md), section 9.

## Linux

`ContrastCore` and `ContrastAuditTesting` import no UI framework, so they are
meant to build and run under `swift test` on Linux. The CI workflow builds and
tests the package in the official `swift:6.0.3-noble` and `swift:6.4.1-noble`
images. Those jobs had not yet run when this README was written, so Linux
support is configured, not yet demonstrated. On Linux, `ContrastPlatformColors`
compiles to a module with no public API.

## What this is not

- **A passing audit does not mean your app is accessible.** It means that the
  pairs you declared meet the ratios for the roles you declared, and nothing
  more. Pairs you did not declare, text over images, focus indicators, motion,
  VoiceOver and everything else are out of scope.
- It does not audit rendered UI, screenshots, gradients or text over photos.
- It does not generate palettes, suggest fixes, simulate color-vision
  deficiencies or convert between color spaces.
- It implements WCAG 2.1 contrast only, not APCA or WCAG 3.
- It does not detect a pair's role from font size or weight.

## Related projects

Checked on 2026-10-25 from each project's README, source or the GitHub API.
The search covered Swift Package Index, GitHub and the web but was not
exhaustive. "Whole-theme test assertion" means one call from a test that checks
many named pairs and fails with one aggregated message.

| Project | What it offers (paraphrased) | Whole-theme test assertion | Last commit | License |
|---|---|---|---|---|
| [InclusiveColor](https://github.com/importRyan/InclusiveColor) (importRyan) | XCTest `AssertInclusive` over arrays of text colors, backgrounds and fonts, with one aggregated failure message at the call site; color-vision simulation ([README](https://raw.githubusercontent.com/importRyan/InclusiveColor/main/README.md), [assertion source](https://raw.githubusercontent.com/importRyan/InclusiveColor/main/Sources/InclusiveColor/Assertions/AssertInclusive+Text.swift)) | Partial: tests a cross product of arrays; no named pairs or variants, no required ratio in the message, no waivers or baseline | [2021-04-30](https://api.github.com/repos/importRyan/InclusiveColor/commits?per_page=1) | BSD 3-Clause plus the MIT license of the project it forks ([LICENSE](https://raw.githubusercontent.com/importRyan/InclusiveColor/main/LICENSE.md)) |
| [YCoreUI](https://github.com/codeandtheory/YCoreUI) (codeandtheory) | UIColor contrast extensions (WCAG 2.0); the README shows a test loop over pairs and trait collections to copy ([README](https://raw.githubusercontent.com/codeandtheory/YCoreUI/main/README.md)) | Partial: an example to copy, one assertion per pair | [2023-04-11](https://api.github.com/repos/codeandtheory/YCoreUI/commits?per_page=1), archived | Apache-2.0 ([API](https://api.github.com/repos/codeandtheory/YCoreUI)) |
| [ContrastKit](https://github.com/markbattistella/ContrastKit) (markbattistella) | Shade generation, readable-color selection, per-pair ratio and conformance checks | No | [2026-09-05](https://api.github.com/repos/markbattistella/ContrastKit/commits?per_page=1) | MIT ([API](https://api.github.com/repos/markbattistella/ContrastKit)) |
| [ColorKit](https://github.com/agisilaos/ColorKit) (agisilaos) | Broad SwiftUI color package, including per-pair WCAG assessment; an example app prints a report for a list of pairs ([example](https://raw.githubusercontent.com/agisilaos/ColorKit/main/Examples/ContrastPairReport/README.md)) | No | [2026-10-08](https://api.github.com/repos/agisilaos/ColorKit/commits?per_page=1) | MIT ([API](https://api.github.com/repos/agisilaos/ColorKit)) |
| [ColorsKit](https://github.com/ckdash-git/ColorsKit) (ckdash-git) | Color utilities for SwiftUI and UIKit with a per-pair AA/AAA check | No | [2025-10-25](https://api.github.com/repos/ckdash-git/ColorsKit/commits?per_page=1) | Apache-2.0 ([API](https://api.github.com/repos/ckdash-git/ColorsKit)) |
| [WCAG-Colors](https://github.com/chrs1885/WCAG-Colors) (chrs1885) | UIColor/NSColor contrast ratio, conformance level and readable-color suggestions | No | [2021-10-02](https://api.github.com/repos/chrs1885/WCAG-Colors/commits?per_page=1) | MIT ([API](https://api.github.com/repos/chrs1885/WCAG-Colors)) |
| [Color](https://github.com/soffes/Color) (soffes) | Pure-Swift color utilities with WCAG 2.0 contrast ratios | No | [2022-12-07](https://api.github.com/repos/soffes/Color/commits?per_page=1) | MIT ([API](https://api.github.com/repos/soffes/Color)) |
| Apple [`performAccessibilityAudit`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)) | UI-test audit of the rendered screen, with a contrast category ([audit types](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype/contrast)) | Different approach: rendered screens in a UI test, not theme definitions | n/a | Apple SDK (XCUIAutomation framework) |
| [accessibility_test](https://pub.dev/packages/accessibility_test) (Dart, Flutter) | `themeTest()` checks the color pairs of a Flutter theme and names the colors and ratio on failure | Yes, for Flutter; marked discontinued | n/a | Apache-2.0 ([pub.dev](https://pub.dev/packages/accessibility_test)) |

InclusiveColor is the closest prior art in Swift, and this package is not the
first XCTest contrast assertion for Swift. What ContrastAudit adds is the
combination: caller-named pairs checked in named variants, the required ratio
in every failure line, waivers with reasons, a baseline that only ratchets, a
Swift Testing helper next to the XCTest one, and a core with no UI-framework
imports.

## Requirements

- Swift 6.0 or later (`swift-tools-version: 6.0`). Development and the
  recorded test runs used Xcode 27.1 (Swift 6.4) on macOS 26.6; CI is
  configured for Xcode 26.6 and the Swift 6.0.3 and 6.4.1 Linux images.
- Platforms: macOS 10.15, iOS 13, tvOS 13, watchOS 6 and visionOS 1. Linux is
  configured in CI but not yet demonstrated (see [Linux](#linux)). The AppKit
  bridge needs macOS 11; the SwiftUI bridge needs macOS 14, iOS 17, tvOS 17,
  watchOS 10 or visionOS 1.
- No third-party dependencies.

## More

- [DESIGN.md](DESIGN.md): the API, the WCAG sources, and every behavior choice
  with its reasoning.
- [CONTRIBUTING.md](CONTRIBUTING.md): building, testing, the reference-vector
  check and the leak scan.
- [CHANGELOG.md](CHANGELOG.md)
- [docs/verification.md](docs/verification.md): the commands and results of the
  last clean-checkout run.

## License

MIT. See [LICENSE](LICENSE).
