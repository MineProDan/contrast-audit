# Verification

Run on 2026-10-25 against a fresh `git clone` of this repository at commit
`f51fffd`. Afterwards only this file and the install URL in README.md changed.
Absolute path prefixes are removed from the output below. Only summary lines
are shown. The `✔`, `━` and `✘` characters are Swift Testing's own output.

Toolchain: Xcode 27.1, Apple Swift 6.4 (swiftlang-6.4.0.34.1), macOS 26.6,
arm64. CI results are summarized at the end.

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

## CI (GitHub Actions)

Workflow run 40273338878 at commit `d8a80ec`, 2026-10-26: all six jobs passed.
Summary lines from the job logs:

```
macOS (Xcode 26.6, Swift 6.3.3)
━ Test run with 119 tests in 18 suites passed with 4 known issues.
(plus the import check, the vector check, and the demo pass and intended failure)

macOS (Xcode 16.0, Swift 6.0)
Test run with 119 tests passed with 4 known issues.
Executed 4 tests, with 0 failures (0 unexpected)

iOS simulator (Xcode 26.6, iPhone 17 Pro, iOS 26.5)
** TEST SUCCEEDED **

Linux (swift:6.4.1-noble)
━ Test run with 95 tests in 14 suites passed with 2 known issues.
━ Test run with 4 tests in 1 suite passed with 2 known issues.
Executed 2 tests, with 0 failures (0 unexpected)

Linux (swift:6.0.3-noble)
Test run with 99 tests passed with 4 known issues.
Executed 2 tests, with 0 failures (0 unexpected)

Leak scan (generic checks): clean
```

Swift 6.0 prints its summary symbol as a cross even when the run passes with
known issues; the word "passed" and the job result are what count. On Linux,
XCTest runs only the two passing-path helper tests, because the
`XCTExpectFailure` tests are limited to Apple platforms.
