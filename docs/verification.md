# Verification

Run on 2026-10-25 against a fresh `git clone` of this repository at commit
`f51fffd`. Afterwards only this file and the install URL in README.md changed.
Absolute path prefixes are removed from the output below. Only summary lines
are shown. The `✔`, `━` and `✘` characters are Swift Testing's own output.

Toolchain: Xcode 27.1, Apple Swift 6.4 (swiftlang-6.4.0.34.1), macOS 26.6,
arm64. The CI workflow also targets Xcode 26.6, Xcode 16.0 (Swift 6.0) and the
Linux images `swift:6.0.3-noble` and `swift:6.4.1-noble`; those had not run
when this file was written.

## Build

```
swift build -Xswiftc -warnings-as-errors
Build complete! (8.28 sec)
```

## Tests (macOS)

```
swift test
━ Test run with 95 tests in 14 suites passed after 0.043 seconds with 2 known issues.
✔ Test run with 20 tests in 3 suites passed after 0.027 seconds.
━ Test run with 4 tests in 1 suite passed after 0.001 seconds with 2 known issues.
Executed 4 tests, with 0 failures (0 unexpected)
exit 0
```

The 95-test run is ContrastCoreTests, the 20-test run ContrastPlatformColorsTests
and the 4-test runs ContrastAuditTestingTests (Swift Testing and XCTest). The
known issues are intended: failure-path tests that check the exact message
inside `withKnownIssue`, and the test of the tolerant JSON comparison.

## Tests (iOS simulator)

```
xcodebuild test -scheme ContrastAudit-Package -destination 'platform=iOS Simulator,id=<iPhone 18 Pro, iOS 27.0>'
━ Test run with 95 tests in 14 suites passed after 0.116 seconds with 2 known issues.
✔ Test run with 17 tests in 3 suites passed after 0.067 seconds.
━ Test run with 4 tests in 1 suite passed after 0.015 seconds with 2 known issues.
** TEST SUCCEEDED **
```

## Independent reference vectors

```
python3 -I scripts/verify_vectors.py --check
Tests/ContrastCoreTests/Fixtures/vectors.json matches (838 cases)
exit 0
```

## ContrastCore imports and unsafe constructs

```
grep -rnE '^\s*(public |internal |@testable )?import (SwiftUI|UIKit|AppKit|XCTest|Testing)' Sources/ContrastCore
(no output) exit 1
grep -rnE 'try!|as!|fatalError|precondition|print\(' Sources
(no output) exit 1
```

## Leak scan (generic checks)

```
bash scripts/leak_scan.sh --no-denylist
[denylist] skipped (--no-denylist)
[long-number] 0 found
[credential] 0 found
[abs-path] 0 found
leak_scan: clean
```

## Demo package

```
cd Examples/ThemeAuditDemo && swift test
✔ Test run with 2 tests in 1 suite passed after 0.001 seconds.
Executed 1 test, with 0 failures (0 unexpected)

cd Examples/ThemeAuditDemo && DEMO_SHOW_FAILURE=1 swift test
exit 1; the recorded issue matches docs/example-output.txt line for line
```
