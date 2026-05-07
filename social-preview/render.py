#!/usr/bin/env python3
"""Universal social preview renderer.

Substitutes parametric placeholders into the chassis template and writes the
SVG to disk. The caller (workflow) hands the SVG to resvg for PNG rendering.

Auto-fit logic:
  - len(namespace) <=  7 chars  → single line @ 132 px
  - len(namespace) 8..14 chars  → single line, shrunk to fit ≥ 48 px
  - len(namespace) >= 15 chars  → CamelCase split, two lines @ 84 px each

The renderer knows nothing about tiers, orgs, or brand — every brand input
arrives as an argument.

Provenance: Research/social-preview-cards-ecosystem-strategy.md
"""

import argparse
import re
import sys

# Right-pane safe area. Gradient ends at x=520; text starts at x=580
# (60 px left gap). Apply symmetric 60 px right gap: text ends at x=1220,
# giving 640 px usable width.
PANE_WIDTH = 640
# Heavy weight (800) Inter glyph-class advances with letter-spacing -2.
# Tuned empirically against rendered text — Inter Heavy caps are wider
# than the often-cited 0.62em average due to W/M outliers and dense
# weight stems. Conservative side: prefer slight under-fill over clipping.
ADVANCE_UPPER = 0.70
ADVANCE_LOWER = 0.55
ADVANCE_SPACE = 0.30
# Legibility floor at thumbnail
MIN_FONT_SIZE = 48
DEFAULT_FONT_SIZE = 132
TWO_LINE_FONT_SIZE = 84


def text_advance(text: str) -> float:
    """Estimated text width in em units (multiply by font_size for px)."""
    total = 0.0
    for c in text:
        if c == " ":
            total += ADVANCE_SPACE
        elif c.isupper() or c.isdigit():
            total += ADVANCE_UPPER
        else:
            total += ADVANCE_LOWER
    return total


def split_two_lines(name: str) -> tuple[str, str]:
    """Split into two lines on the boundary closest to the midpoint.

    Preference order:
      1. Explicit '|' separator (manual override from displayName)
      2. Whitespace closest to midpoint
      3. CamelCase boundary closest to midpoint
    """
    if "|" in name:
        l, _, r = name.partition("|")
        return l.strip(), r.strip()
    if " " in name:
        spaces = [i for i, c in enumerate(name) if c == " "]
        mid = len(name) / 2
        best = min(spaces, key=lambda b: abs(b - mid))
        return name[:best], name[best + 1 :]
    boundaries = [m.start() for m in re.finditer(r"(?<!^)(?=[A-Z])", name)]
    if not boundaries:
        return name, ""
    mid = len(name) / 2
    best = min(boundaries, key=lambda b: abs(b - mid))
    return name[:best], name[best:]


def _one_line(namespace: str, size: int) -> dict[str, str]:
    return {
        "L1": namespace, "L2": "",
        "SIZE": str(size),
        "Y1": "350", "Y2": "-100",
        "SUBLINE_Y": "410", "CAPTION_Y": "470",
    }


def _two_line(l1: str, l2: str, size: int) -> dict[str, str]:
    return {
        "L1": l1, "L2": l2,
        "SIZE": str(size),
        "Y1": "310", "Y2": str(310 + size),
        "SUBLINE_Y": str(310 + size + 60),
        "CAPTION_Y": str(310 + size + 113),
    }


def fit(namespace: str) -> dict[str, str]:
    """Compute layout (font-size, lines, y-positions) for the namespace.

    Priority: full-size single-line → shrunk single-line (if still ≥
    TWO_LINE_FONT_SIZE) → full-size two-line → shrunk two-line. Two-line
    only kicks in when shrinking single-line would drop below the two-line
    full size — at that point two-line preserves more weight per line.
    """
    text = namespace.replace("|", " ")
    advance_em = text_advance(text)
    if advance_em * DEFAULT_FONT_SIZE <= PANE_WIDTH:
        return _one_line(namespace, DEFAULT_FONT_SIZE)

    one_line_min_size = int(PANE_WIDTH / advance_em)
    if one_line_min_size >= TWO_LINE_FONT_SIZE:
        return _one_line(namespace, one_line_min_size)

    l1, l2 = split_two_lines(namespace)
    if l2:
        longest = max(text_advance(l1), text_advance(l2))
        if longest * TWO_LINE_FONT_SIZE <= PANE_WIDTH:
            return _two_line(l1, l2, TWO_LINE_FONT_SIZE)
        size = int(PANE_WIDTH / longest)
        if size >= MIN_FONT_SIZE:
            return _two_line(l1, l2, size)

    if one_line_min_size >= MIN_FONT_SIZE:
        return _one_line(namespace, one_line_min_size)
    return _one_line(namespace, MIN_FONT_SIZE)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--template", required=True)
    p.add_argument("--namespace", required=True)
    p.add_argument("--package-name", required=True)
    p.add_argument("--accent-from", required=True)
    p.add_argument("--accent-to", required=True)
    p.add_argument("--accent-text", required=True)
    p.add_argument("--caption", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    layout = fit(args.namespace)
    with open(args.template) as f:
        svg = f.read()
    substitutions = {
        "{{ACCENT_FROM}}": args.accent_from,
        "{{ACCENT_TO}}": args.accent_to,
        "{{ACCENT_TEXT}}": args.accent_text,
        "{{CAPTION}}": args.caption,
        "{{NAMESPACE_L1}}": layout["L1"],
        "{{NAMESPACE_L2}}": layout["L2"],
        "{{NAMESPACE_SIZE}}": layout["SIZE"],
        "{{NAMESPACE_Y1}}": layout["Y1"],
        "{{NAMESPACE_Y2}}": layout["Y2"],
        "{{PACKAGE_NAME}}": args.package_name,
        "{{SUBLINE_Y}}": layout["SUBLINE_Y"],
        "{{CAPTION_Y}}": layout["CAPTION_Y"],
    }
    for k, v in substitutions.items():
        svg = svg.replace(k, v)
    with open(args.output, "w") as f:
        f.write(svg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
