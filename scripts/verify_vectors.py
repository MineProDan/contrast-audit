#!/usr/bin/env python3
"""Independent WCAG 2.1 contrast reference vectors for ContrastCore.

Written from the WCAG 2.1 definitions of relative luminance and contrast
ratio, not from the Swift code, so that the two implementations check each
other. Standard library only; run it with `python3 -I`.

    python3 -I scripts/verify_vectors.py          # write the fixture
    python3 -I scripts/verify_vectors.py --check  # compare, exit 1 on change

Definitions used (https://www.w3.org/TR/WCAG21/, glossary):
  - linear channel: c / 12.92 if c <= 0.04045, else ((c + 0.055) / 1.055) ** 2.4
  - relative luminance: 0.2126 R + 0.7152 G + 0.0722 B
  - contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05)
Transparency follows DESIGN.md 5.3: source-over on gamma-encoded components,
a translucent background first over its opaque backdrop, then a translucent
foreground over the result.

The Swift test ContrastCoreTests/ReferenceVectorTests compares every case with
a relative tolerance of 1e-9.
"""

import argparse
import json
import math
import pathlib
import random
import sys

SEED = 20261025
RANDOM_OPAQUE_CASES = 200
RANDOM_TRANSLUCENT_CASES = 120
# Ratios are written with full precision. --check compares them with this
# relative tolerance, so a last-bit difference in the platform's pow() does
# not count as a change, while any real change does.
CHECK_TOLERANCE = 1e-12

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "Tests" / "ContrastCoreTests" / "Fixtures" / "vectors.json"


def parse_hex(text):
    """Return (r, g, b, a) as integers 0-255 from #RGB, #RGBA, #RRGGBB or #RRGGBBAA."""
    digits = text[1:] if text.startswith("#") else text
    if len(digits) in (3, 4):
        digits = "".join(d + d for d in digits)
    if len(digits) not in (6, 8):
        raise ValueError("bad hex: " + text)
    values = [int(digits[i:i + 2], 16) for i in range(0, len(digits), 2)]
    if len(values) == 3:
        values.append(255)
    return tuple(values)


def to_unit(rgba8):
    return tuple(v / 255 for v in rgba8)


def over(top, bottom):
    """Source-over of a color on an opaque color, gamma-encoded, result opaque."""
    alpha = top[3]
    mixed = [top[i] * alpha + bottom[i] * (1 - alpha) for i in range(3)]
    return (mixed[0], mixed[1], mixed[2], 1.0)


def channel_to_linear(value):
    if value <= 0.04045:
        return value / 12.92
    return math.pow((value + 0.055) / 1.055, 2.4)


def luminance(color):
    red, green, blue = (channel_to_linear(c) for c in color[:3])
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(foreground_hex, background_hex, backdrop_hex=None):
    background = to_unit(parse_hex(background_hex))
    if background[3] < 1:
        if backdrop_hex is None:
            raise ValueError("translucent background needs a backdrop")
        backdrop = to_unit(parse_hex(backdrop_hex))
        if backdrop[3] < 1:
            raise ValueError("backdrop must be opaque")
        background = over(background, backdrop)
    foreground = to_unit(parse_hex(foreground_hex))
    if foreground[3] < 1:
        foreground = over(foreground, background)
    a, b = luminance(foreground), luminance(background)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def hex6(rng):
    return "#%02X%02X%02X" % (rng.randrange(256), rng.randrange(256), rng.randrange(256))


def build_cases():
    cases = []

    def add(kind, foreground, background, backdrop=None):
        cases.append({
            "kind": kind,
            "foreground": foreground,
            "background": background,
            "backdrop": backdrop,
            "ratio": contrast(foreground, background, backdrop),
        })

    # Published and boundary reference values.
    add("reference", "#000000", "#FFFFFF")
    add("reference", "#FFFFFF", "#000000")
    add("reference", "#767676", "#FFFFFF")
    add("reference", "#777777", "#FFFFFF")
    add("reference", "#1E2B37", "#FFFFFF")
    add("reference", "#8B959F", "#FFFFFF")

    for level in range(256):
        gray = "#%02X%02X%02X" % (level, level, level)
        add("gray-on-black", gray, "#000000")
    for level in range(256):
        gray = "#%02X%02X%02X" % (level, level, level)
        add("gray-on-white", gray, "#FFFFFF")

    rng = random.Random(SEED)
    for _ in range(RANDOM_OPAQUE_CASES):
        foreground, background = hex6(rng), hex6(rng)
        # Exercise the other accepted spellings now and then.
        style = rng.randrange(4)
        if style == 1:
            foreground = foreground.lower()
        elif style == 2:
            background = background[1:]
        elif style == 3:
            foreground = "#" + "".join(rng.choice("0123456789ABCDEF") for _ in range(3))
        add("random-opaque", foreground, background)

    alpha_edges = [0, 1, 127, 128, 254, 255]
    for index in range(RANDOM_TRANSLUCENT_CASES):
        shape = index % 3
        alpha = alpha_edges[index // 3] if index // 3 < len(alpha_edges) else rng.randrange(256)
        alpha_text = "%02X" % alpha
        if shape == 0:
            add("translucent-foreground", hex6(rng) + alpha_text, hex6(rng))
        elif shape == 1:
            add("translucent-background", hex6(rng), hex6(rng) + alpha_text, hex6(rng))
        else:
            other = "%02X" % rng.randrange(256)
            add("both-translucent", hex6(rng) + other, hex6(rng) + alpha_text, hex6(rng))

    return cases


def render(cases):
    document = {
        "generator": "scripts/verify_vectors.py",
        "seed": SEED,
        "cases": cases,
    }
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


def compare(expected_cases, actual_cases):
    """Return a list of human-readable differences."""
    differences = []
    if len(expected_cases) != len(actual_cases):
        differences.append("case count %d, regenerated %d" % (len(actual_cases), len(expected_cases)))
    for index, (want, have) in enumerate(zip(expected_cases, actual_cases)):
        for key in ("kind", "foreground", "background", "backdrop"):
            if want.get(key) != have.get(key):
                differences.append("case %d: %s is %r, regenerated %r" % (index, key, have.get(key), want.get(key)))
        ratio = have.get("ratio")
        if not isinstance(ratio, (int, float)) or not math.isclose(
                ratio, want["ratio"], rel_tol=CHECK_TOLERANCE, abs_tol=0.0):
            differences.append("case %d: ratio is %r, regenerated %r" % (index, ratio, want["ratio"]))
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="regenerate in memory and exit 1 if the fixture differs")
    args = parser.parse_args()

    cases = build_cases()
    text = render(cases)
    relative = FIXTURE.relative_to(ROOT)

    if not args.check:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(text, encoding="utf-8")
        print("wrote %d cases to %s" % (len(cases), relative))
        return 0

    try:
        stored_text = FIXTURE.read_text(encoding="utf-8")
        stored = json.loads(stored_text)
    except (OSError, ValueError) as error:
        print("cannot read %s: %s" % (relative, error), file=sys.stderr)
        return 1
    if stored_text == text:
        print("%s matches (%d cases)" % (relative, len(cases)))
        return 0
    differences = []
    if stored.get("seed") != SEED:
        differences.append("seed is %r, expected %r" % (stored.get("seed"), SEED))
    differences += compare(cases, stored.get("cases", []))
    if differences:
        for line in differences[:20]:
            print(line, file=sys.stderr)
        print("%s differs: %d differences" % (relative, len(differences)), file=sys.stderr)
        return 1
    print("%s matches within %g relative (%d cases; text differs only in last digits)"
          % (relative, CHECK_TOLERANCE, len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
