# ThemeAuditDemo

A separate package that depends on ContrastAudit by local path and audits two
invented themes at WCAG 2.1 AA:

- `Orchard` passes in light and dark, including a translucent surface measured
  over a declared backdrop.
- `Ember` fails on purpose: one body-text pair and one UI-component pair are
  too faint, and a logotype pair is covered by a waiver.

Run from this folder:

```sh
swift test                        # Orchard only; passes
DEMO_SHOW_FAILURE=1 swift test    # also runs Ember, which fails
```

The second command's failure output is captured in `docs/example-output.txt`
at the repository root.
