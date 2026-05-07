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

# Right-pane safe area: x=580..1240 → 660 px wide
PANE_WIDTH = 660
# Heavy weight (800) Inter advance ≈ 0.55em with letter-spacing -2
CHAR_ADVANCE_EM = 0.55
# Legibility floor at thumbnail
MIN_FONT_SIZE = 48
DEFAULT_FONT_SIZE = 132
TWO_LINE_FONT_SIZE = 84


def split_camelcase(name: str) -> tuple[str, str]:
    """Split CamelCase on the boundary closest to the midpoint.

    >>> split_camelcase("IntermediateRepresentation")
    ('Intermediate', 'Representation')
    >>> split_camelcase("AlgebraSemilattice")
    ('Algebra', 'Semilattice')
    """
    boundaries = [m.start() for m in re.finditer(r"(?<!^)(?=[A-Z])", name)]
    if not boundaries:
        return name, ""
    mid = len(name) / 2
    best = min(boundaries, key=lambda b: abs(b - mid))
    return name[:best], name[best:]


def fit(namespace: str) -> dict[str, str]:
    """Compute layout (font-size, lines, y-positions) for the namespace.

    Y baselines are tuned so the content cluster sits at or slightly below
    canvas optical center, balancing the pyramid glyph's heavy base.
    """
    n = len(namespace)
    one_line_default_width = n * CHAR_ADVANCE_EM * DEFAULT_FONT_SIZE
    if one_line_default_width <= PANE_WIDTH:
        return {
            "L1": namespace, "L2": "",
            "SIZE": str(DEFAULT_FONT_SIZE),
            "Y1": "350", "Y2": "-100",
            "SUBLINE_Y": "410", "CAPTION_Y": "470",
        }
    one_line_min_size = PANE_WIDTH / (n * CHAR_ADVANCE_EM)
    if one_line_min_size >= MIN_FONT_SIZE:
        size = int(one_line_min_size)
        return {
            "L1": namespace, "L2": "",
            "SIZE": str(size),
            "Y1": "350", "Y2": "-100",
            "SUBLINE_Y": "410", "CAPTION_Y": "470",
        }
    l1, l2 = split_camelcase(namespace)
    longest = max(len(l1), len(l2))
    two_line_default_width = longest * CHAR_ADVANCE_EM * TWO_LINE_FONT_SIZE
    if two_line_default_width <= PANE_WIDTH:
        size = TWO_LINE_FONT_SIZE
    else:
        size = int(PANE_WIDTH / (longest * CHAR_ADVANCE_EM))
    return {
        "L1": l1, "L2": l2,
        "SIZE": str(size),
        "Y1": "310", "Y2": str(310 + size),
        "SUBLINE_Y": str(310 + size + 60),
        "CAPTION_Y": str(310 + size + 113),
    }


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
