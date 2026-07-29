#!/usr/bin/env python3
"""render-gitignore.py — render a package `.gitignore` from canon.

Companion to sync-gitignore.yml. Canon is `canon/gitignore-package.txt`.

A package `.gitignore` has two parts:

    # ========== CANONICAL (auto-synced, do not edit) ==========
    ...                                   <- owned by canon, replaced wholesale
    # ========== END CANONICAL ==========
    ...                                   <- owned by the package, PRESERVED

This script emits canon's canonical section followed by the target's own
content after `END CANONICAL`. Nothing a package wrote is discarded.

A pre-canonical file has no marker. Its entire content is preserved as local
overrides beneath a freshly prepended canonical section, per the 2026-03-12
gitignore-sync-strategy decision — the alternative, replacing it, would delete
rules a package deliberately added and is not recoverable from the diff alone.

Rendering is deterministic and byte-compared by the caller, so a repository
that is already conformant produces no commit.

Usage:  render-gitignore.py <canon> <target-gitignore-or-missing>
Writes the rendered file to stdout. Exit 0 always unless canon is unusable (2).
"""
from __future__ import annotations

import sys
from pathlib import Path

CANONICAL_END = "# ========== END CANONICAL =========="

PRESERVED_HEADER = """
# ========== LOCAL OVERRIDES ==========
# Preserved verbatim from this package's pre-canonical .gitignore. Rules here
# may duplicate the canonical section above; that is harmless, and deleting
# them is not this script's call to make.
"""


def render(canon: str, existing: str | None) -> str:
    index = canon.find(CANONICAL_END)
    if index < 0:
        raise ValueError(f"canon has no {CANONICAL_END} marker")
    canonical = canon[: index + len(CANONICAL_END)] + "\n"

    if existing is None:
        # No file at all: canon already carries an empty LOCAL OVERRIDES block.
        return canon

    marker = existing.find(CANONICAL_END)
    if marker >= 0:
        return canonical + existing[marker + len(CANONICAL_END) + 1 :]

    return canonical + PRESERVED_HEADER + "\n" + existing.lstrip("\n")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    canon_path, target_path = Path(argv[1]), Path(argv[2])
    if not canon_path.is_file():
        print(f"canon not found: {canon_path}", file=sys.stderr)
        return 2
    canon = canon_path.read_text(encoding="utf-8")
    existing = target_path.read_text(encoding="utf-8") if target_path.is_file() else None
    try:
        sys.stdout.write(render(canon, existing))
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
