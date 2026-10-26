# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-25

First release.

### Added

- `ContrastCore`, with no UI-framework or test-framework imports:
  - `SRGBColor`, created from components in 0...1 (throws instead of clamping),
    from 8-bit components, or from `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`
    hex strings.
  - WCAG 2.1 relative luminance and `ContrastRatio`, which compares unrounded
    values and displays them truncated to two decimals, never rounded up.
  - `PairRole` (`.bodyText`, `.largeText`, `.uiComponent`) and
    `ConformanceLevel` (`.aa`, `.aaa`) with the WCAG 2.1 requirements.
  - `Theme`, `ColorPair` and `Variant` for declaring pairs once and auditing
    them in every variant.
  - Explicit backdrops for translucent backgrounds; source-over compositing on
    gamma-encoded sRGB; no assumed white background.
  - `Waiver` for reviewed exceptions with a reason and optional expiry note.
  - `Baseline` for recording known failures that may not get worse, with a
    versioned JSON format.
  - `AuditReport` with `summary`, the aggregated `failureDescription`,
    `markdown()` and `json()`, and `CheckResult` for inspecting checks in code.
  - Configuration mistakes (missing or malformed colors, duplicates, empty
    themes, backdrop problems, baseline level mismatch) reported as
    `AuditProblem`s instead of crashes.
- `ContrastAuditTesting`: `ContrastAudit.assertPasses` for XCTest and
  `ContrastAudit.expectPasses` for Swift Testing, each recording one failure
  with the aggregated message at the caller's source location.
- `ContrastPlatformColors`: `SRGBColor(resolving:appearance:)` for `NSColor`,
  `SRGBColor(resolving:with:)` for `UIColor` and `SRGBColor(resolving:in:)` for
  SwiftUI `Color`, each with an explicit appearance, converting to sRGB without
  clamping.
- `scripts/verify_vectors.py`, an independent standard-library Python
  implementation that generates the reference-vector fixture used by the tests.
- `Examples/ThemeAuditDemo`, a separate package with one passing and one
  intentionally failing invented theme.
- `scripts/leak_scan.sh` and a GitHub Actions workflow for macOS (Xcode 26.6 and
  Xcode 16.0 / Swift 6.0), the iOS
  simulator, Linux and the leak scan.

[0.1.0]: https://github.com/MineProDan/contrast-audit/releases/tag/v0.1.0
