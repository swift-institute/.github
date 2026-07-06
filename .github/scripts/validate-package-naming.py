#!/usr/bin/env python3
"""validate-package-naming.py — org-scoped package repo-naming rules.

Naming-cluster host script (mirrors the validate-file-naming.py precedent:
related naming rules share one script). Rules checked (v1):

  [PRIM-NAME-001]  Every PACKAGE repo in the swift-primitives org MUST use
                   the `-primitives` suffix. Non-package repos (no
                   Package.swift — Research, Scripts, xcworkspaces, org
                   sites) are out of scope.

Queued for this script when their promotes land: [PKG-NAME-014] org-prefix
collision pre-check.

Org derivation: the `<repo-name>` argument's owner part. Harness fixtures
(owner `swift-institute-test/` per tests/run.sh) encode the intended org in
the scenario dir name via a double-underscore: `swift-primitives__swift-foo`
is checked as org swift-primitives, repo swift-foo (pilot-10 fixture
carve-out pattern).

Output: TSV findings `repo<TAB>PRIM-NAME-001<TAB>message` (validate_lib.emit).

Usage:
  validate-package-naming.py <repo-name> <repo-root>

Provenance: REPORT-corpus-review.md §5 NONE batch, promoted via /promote-rule
per HANDOFF-mechanization-arc W1. Outcome record:
swift-institute/Audits/PROMOTE-PRIM-NAME-001-2026-07-06.md.
"""
from __future__ import annotations

import sys
from pathlib import Path

from validate_lib import emit

RULE = "PRIM-NAME-001"
FIXTURE_OWNER = "swift-institute-test"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])
    if not root.is_dir():
        print(f"# error: repo root not found: {root}", file=sys.stderr)
        return 2

    owner, _, name = repo.rpartition("/")
    if owner == FIXTURE_OWNER and "__" in name:
        owner, _, name = name.partition("__")

    if owner != "swift-primitives":
        return 0  # rule is scoped to the primitives org
    if not (root / "Package.swift").is_file():
        return 0  # non-package repo (Research, Scripts, org site, workspace)

    if not name.endswith("-primitives"):
        emit(repo, RULE,
             f"package repo '{name}' in the swift-primitives org lacks the "
             f"'-primitives' suffix ([PRIM-NAME-001]); rename the repo or "
             f"record a principal-sanctioned exception in the outcome record")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
