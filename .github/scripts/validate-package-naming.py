#!/usr/bin/env python3
"""validate-package-naming.py — org-scoped package repo-naming rules.

Naming-cluster host script (mirrors the validate-file-naming.py precedent:
related naming rules share one script). Rules checked (v1):

  [PRIM-NAME-001]  Every PACKAGE repo in the swift-primitives org MUST use
                   the `-primitives` suffix. Non-package repos (no
                   Package.swift — Research, Scripts, xcworkspaces, org
                   sites) are out of scope.
  [PKG-NAME-014]   Org-prefix on pack-targets: a package MUST NOT declare a
                   non-test target whose name collides with a target of a
                   DIRECT dependency (SwiftPM rejects duplicate module names,
                   but only at a consumer's compile time — this is the
                   authoring-time pre-check). Dep manifests resolve via path
                   deps on disk and url deps against the local org mirrors;
                   deps without a local manifest are skipped. Direct deps
                   only in v1 (the canonical layered-vocabulary instance is
                   a direct edge).

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

import re

from validate_lib import emit

RULE = "PRIM-NAME-001"
RULE_COLLISION = "PKG-NAME-014"
FIXTURE_OWNER = "swift-institute-test"

RE_TARGET = re.compile(
    r'\.(?:target|executableTarget|macro)\s*\(\s*name:\s*"([^"]+)"')
RE_URL_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?url:\s*"([^"]+)"')
RE_PATH_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"([^"]+)"')


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def non_test_targets(manifest_text: str) -> set[str]:
    return set(RE_TARGET.findall(strip_comments(manifest_text)))


def dep_manifest_paths(manifest_text: str, root: Path) -> dict[str, Path]:
    """{dep-name → local Package.swift path} for direct deps resolvable on
    this machine (path deps; url deps whose repo exists in an org mirror
    two levels up from the host root)."""
    text = strip_comments(manifest_text)
    out: dict[str, Path] = {}
    for rel in RE_PATH_DEP.findall(text):
        d = (root / rel).resolve()
        if (d / "Package.swift").is_file():
            out[d.name] = d / "Package.swift"
    dev = root.resolve().parent.parent
    for url in RE_URL_DEP.findall(text):
        parts = url.rstrip("/").split("/")
        if len(parts) < 2:
            continue
        name = parts[-1][:-4] if parts[-1].endswith(".git") else parts[-1]
        candidate = dev / parts[-2] / name / "Package.swift"
        if candidate.is_file():
            out[name] = candidate
    return out


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

    if not (root / "Package.swift").is_file():
        return 0  # non-package repo (Research, Scripts, org site, workspace)

    # [PRIM-NAME-001] — primitives-org repo suffix.
    if owner == "swift-primitives" and not name.endswith("-primitives"):
        emit(repo, RULE,
             f"package repo '{name}' in the swift-primitives org lacks the "
             f"'-primitives' suffix ([PRIM-NAME-001]); rename the repo or "
             f"record a principal-sanctioned exception in the outcome record")

    # [PKG-NAME-014] — target-name collisions with direct deps.
    manifest_text = (root / "Package.swift").read_text(encoding="utf-8",
                                                       errors="replace")
    own = non_test_targets(manifest_text)
    if own:
        for dep_name, dep_manifest in sorted(
                dep_manifest_paths(manifest_text, root).items()):
            dep_targets = non_test_targets(
                dep_manifest.read_text(encoding="utf-8", errors="replace"))
            for clash in sorted(own & dep_targets):
                emit(repo, RULE_COLLISION,
                     f"target '{clash}' collides with a target of direct "
                     f"dependency '{dep_name}' — SwiftPM rejects duplicate "
                     f"module names at consumer compile time; prefix the "
                     f"pack-target per [PKG-NAME-014]")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
