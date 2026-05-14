#!/usr/bin/env python3
"""validate-permissions-shape.py — verify [CI-090] + [CI-097] trigger-shape permissions.

Pilot 27 of `/promote-rule` (2026-05-14) — companion to validate-permissions-shape.yml.

Single-repo multi-file integrity check sub-shape (compose-in-script for paired
rules sharing the same trigger-shape detection point).

Rules checked:
  [CI-090]  Workflow-level `permissions:` MUST be applied per trigger shape:
              - reusable (workflow_call only)  → OMIT top-level permissions
              - standalone (schedule / dispatch / push / pull_request only)
                → DECLARE top-level permissions (`{}` floor or named grants)
              - combined (workflow_call + others) → OMIT top-level permissions
                (treat as reusable per the workflow_call intersection rule)

  [CI-097]  A workflow_call reusable MUST NOT declare workflow-level
            `permissions: {}` (deny-all). The intersection rule caps the
            effective grant at zero → `startup_failure` at every caller.

  CI-097 is a specific case of CI-090 (the deny-all-on-reusable case).
  When both rules apply, CI-097 is preferred for diagnostic clarity.

  Discrimination of trigger shape:
    - has_call:       on.workflow_call key present
    - has_standalone: on contains any of (schedule, workflow_dispatch,
                                          push, pull_request)
    - reusable:       has_call AND NOT has_standalone
    - combined:       has_call AND has_standalone (treat as reusable)
    - standalone:     NOT has_call AND has_standalone

Detection shape: PyYAML walk; check top-level `permissions:` key against
trigger-shape derived expectation.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml, parse_on_block

yaml = require_yaml()

STANDALONE_KEYS = ("schedule", "workflow_dispatch", "push", "pull_request")


def check_workflow(repo: str, wf_path: Path) -> int:
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-090", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    on = parse_on_block(data)
    if on is None:
        return 0
    has_call = "workflow_call" in on
    has_standalone = any(k in on for k in STANDALONE_KEYS)
    # Permissions absence vs presence vs empty-dict are three distinct states.
    has_perms_key = "permissions" in data
    perms = data.get("permissions") if has_perms_key else None
    if has_call:
        # Reusable or combined — treat as reusable per [CI-090] table
        if not has_perms_key:
            return 0  # canonical state
        if perms == {} or perms is None:
            # `permissions: {}` or `permissions: null` — the M2 incident shape
            emit(
                repo,
                "CI-097",
                f"{wf_path.name}: workflow has `on: workflow_call` and "
                f"declares top-level `permissions: {{}}` — per [CI-097] "
                f"this deny-all is forbidden on reusables. The "
                f"workflow_call permissions intersection rule caps the "
                f"effective grant at zero, producing `startup_failure` at "
                f"every caller (the M2 incident shape). Remove the top-"
                f"level block; per-job grants provide the floor.",
            )
            return 1
        # Non-empty permissions on reusable — broader CI-090 violation
        emit(
            repo,
            "CI-090",
            f"{wf_path.name}: workflow has `on: workflow_call` and declares "
            f"top-level `permissions:` — per [CI-090] reusables MUST omit "
            f"top-level permissions. The workflow_call intersection rule "
            f"caps the caller's grant at min(top-level, caller-job). Move "
            f"the grants to per-job `permissions:` blocks instead.",
        )
        return 1
    if has_standalone:
        # Pure standalone — top-level permissions REQUIRED
        if not has_perms_key:
            emit(
                repo,
                "CI-090",
                f"{wf_path.name}: standalone workflow (no `workflow_call:` "
                f"trigger) MUST declare top-level `permissions:` per "
                f"[CI-090] — typically `permissions: {{}}` as a deny-all "
                f"floor with per-job grants overriding. Without the floor, "
                f"the workflow inherits GitHub's repo-default permissions "
                f"(often broader than needed).",
            )
            return 1
    return 0


def main(repo: str, repo_root: str) -> int:
    findings = 0
    workflows_dir = Path(repo_root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return 0
    for wf in sorted(list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))):
        findings += check_workflow(repo, wf)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-permissions-shape.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
