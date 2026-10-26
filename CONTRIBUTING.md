# Contributing

Thanks for taking a look. This is a small package with a deliberately small
API, so please open an issue to discuss a new public type or behavior before
writing it. Bug reports with a failing theme (invented colors are fine) are
the most useful contribution.

## Build and test

From the repository root:

```sh
swift build -Xswiftc -warnings-as-errors
swift test
```

The demo package is a separate package that depends on this one by path:

```sh
cd Examples/ThemeAuditDemo
swift test                        # passes
DEMO_SHOW_FAILURE=1 swift test    # must fail with the message in docs/example-output.txt
```

If you change the failure message format, re-capture `docs/example-output.txt`
from a real run of the second command, and update the README excerpt to match.

The platform bridge tests for UIColor run only on an iOS simulator:

```sh
xcodebuild test -scheme ContrastAudit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Pick any installed simulator; `xcrun simctl list devices available` lists them.

## Reference vectors

`scripts/verify_vectors.py` is an independent implementation of the WCAG 2.1
formulas, written from the specification and using only the Python standard
library. It generates `Tests/ContrastCoreTests/Fixtures/vectors.json`, which
the Swift tests compare against.

```sh
python3 -I scripts/verify_vectors.py --check   # regenerate in memory, fail on any difference
python3 -I scripts/verify_vectors.py           # rewrite the fixture
```

Only rewrite the fixture when the script itself changed for a reason you can
explain in the commit message. Never edit it to match the Swift output.

## Import rule

`ContrastCore` must never import SwiftUI, UIKit, AppKit, XCTest or Testing, so
that it stays fast and runs on Linux. CI checks this with:

```sh
grep -rnE 'import[[:space:]].*(SwiftUI|UIKit|AppKit|XCTest|Testing)([^A-Za-z0-9_]|$)' Sources/ContrastCore
```

which must print nothing.

## Leak scan

`scripts/leak_scan.sh` scans the working tree and the full git history for
long numeric ids, credential patterns, absolute home-directory paths and,
optionally, every string in a private denylist file kept outside the
repository. It prints only counts, file paths and object ids, never the
matched text.

```sh
scripts/leak_scan.sh --no-denylist                 # what CI runs
LEAK_DENYLIST=path/to/denylist.txt scripts/leak_scan.sh
```

Known false positives go in `scripts/leak_allowlist.txt`, one
`<check> <path-glob>` per line, each with a comment explaining why. Never
commit a denylist.

## Style

- A small, focused public API. If a type does not earn its place, leave it out.
- Library code has no force-unwraps, no `fatalError` on user input and no
  `print`.
- Every public symbol has a doc comment saying what it does and when it fails.
- Comments explain why, not what.
- Tests are deterministic and fast; the whole suite runs in seconds.
- Prefer boring, readable Swift over clever Swift.
- No emoji in code, docs or commit messages.
- Compare contrast ratios unrounded; display them only through
  `ContrastRatio.description`.

## Commits

Commit messages are short, imperative and specific, for example
"Report unused waivers in the Markdown footer". One logical change per commit,
with the tests green.

## Example data

Use invented theme names, color names and values in tests, examples and docs.
Do not paste colors, names or text from a real product, including your own,
unless it is already public and you have the right to publish it.
