#!/usr/bin/env python3
"""validate-sub-org-wrappers.py — verify [CI-004b] sub-org wrapper absence.

Pilot 28 of `/promote-rule` (2026-05-14) — companion to validate-sub-org-wrappers.yml.

Single-repo single-file negative-existence check.

Rules checked:
  [CI-004b] Per-authority sub-org `.github` repos MUST NOT host a
            `swift-ci.yml` wrapper. The 4-level workflow_call chain limit
            would break the universal's 6 advisory linter sub-dispatches.

  Named L2 sub-orgs (route through swift-standards layer wrapper):
    swift-ietf, swift-iso, swift-w3c, swift-whatwg, swift-ecma,
    swift-incits, swift-ieee, swift-iec, swift-arm-ltd, swift-intel,
    swift-riscv

  Named L3 sub-orgs (route through swift-foundations layer wrapper):
    swift-linux-foundation, swift-microsoft

  Detection: the validator parses `repo` arg as `<org>/<repo>`; if `<org>`
  is in the named-sub-org set AND `<repo>` is `.github`, the repo is a
  sub-org `.github` repo and `<repo_root>/.github/workflows/swift-ci.yml`
  MUST NOT exist.

  Sunset condition: rule sunsets when GitHub raises the workflow_call
  4-level limit OR universal is refactored to inline advisory linters.

  No file-level carve-outs.

Detection shape: filesystem existence check on a single named file path.
"""
from __future__ import annotations
import sys
from pathlib import Path

L2_SUB_ORGS = frozenset({
    "swift-ietf", "swift-iso", "swift-w3c", "swift-whatwg", "swift-ecma",
    "swift-incits", "swift-ieee", "swift-iec", "swift-arm-ltd",
    "swift-intel", "swift-riscv",
})
L3_SUB_ORGS = frozenset({"swift-linux-foundation", "swift-microsoft"})
ALL_SUB_ORGS = L2_SUB_ORGS | L3_SUB_ORGS


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def determine_sub_org(repo: str, repo_root: Path) -> str | None:
    """Return the sub-org name if this invocation targets a sub-org `.github` repo.

    Production path: parse `repo` arg as `<sub-org>/.github`.
    Test path: read fixture marker `<repo_root>/.github-as-sub-org` (single
    line, sub-org name). The marker exists so test harnesses (whose `repo`
    arg is hardcoded to `swift-institute-test/<fixture-dir>`) can simulate
    a sub-org's `.github` repo without modifying the harness.
    """
    marker = repo_root / ".github-as-sub-org"
    if marker.is_file():
        name = marker.read_text(encoding="utf-8").strip()
        if name in ALL_SUB_ORGS:
            return name
        return None
    parts = repo.split("/", 1)
    if len(parts) != 2:
        return None
    org, name = parts
    if name == ".github" and org in ALL_SUB_ORGS:
        return org
    return None


def main(repo: str, repo_root: str) -> int:
    root = Path(repo_root)
    sub_org = determine_sub_org(repo, root)
    if sub_org is None:
        return 0  # not a sub-org `.github` repo — out of scope
    wf = root / ".github" / "workflows" / "swift-ci.yml"
    if not wf.is_file():
        return 0  # canonical state — no wrapper exists
    parent_layer = "swift-foundations" if sub_org in L3_SUB_ORGS else "swift-standards"
    emit(
        repo,
        "CI-004b",
        f".github/workflows/swift-ci.yml EXISTS at sub-org `{sub_org}/.github` "
        f"— per [CI-004b] sub-org wrappers MUST NOT be created today (GitHub "
        f"Actions `workflow_call` 4-level chain limit would break the "
        f"universal's advisory linter sub-dispatches). Route this sub-org's "
        f"consumers through the parent layer wrapper "
        f"`{parent_layer}/.github/.github/workflows/swift-ci.yml@main` "
        f"instead. Per-authority concerns belong in the universal "
        f"`swift-ci.yml` as advisory jobs filtered by repo-name pattern, "
        f"not as a per-authority wrapper.",
    )
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-sub-org-wrappers.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
