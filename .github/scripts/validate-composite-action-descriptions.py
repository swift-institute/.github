#!/usr/bin/env python3
"""validate-composite-action-descriptions.py — verify [CI-102] description plain-text.

Pilot 25 of `/promote-rule` (2026-05-14).

Single-repo multi-file integrity check: scans every composite action at
`<repo_root>/.github/actions/<name>/action.yml` and asserts no
`description:` field (top-level, per-input, per-output) contains a
`${{ ... }}` expression.

Rules checked:
  [CI-102]  GitHub Actions evaluates expressions at composite-action parse
            time even in description fields; any `${{ ... }}` in a
            description produces HTTP 422. Plain English with backtick
            code-references is required.

  No file-level carve-outs.

Detection shape: PyYAML walk; scan `description` strings at three known
positions; regex match `\\$\\{\\{` against each.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

EXPR_RE = re.compile(r"\$\{\{")


def check_description(repo: str, action_path: Path, location: str, value: object) -> int:
    if isinstance(value, str) and EXPR_RE.search(value):
        emit(
            repo,
            "CI-102",
            f"{action_path.parent.name}/action.yml: {location} description "
            f"contains `${{{{ ... }}}}` expression — per [CI-102] composite-"
            f"action description fields are parsed at composite-load time "
            f"and reject all expression syntax (HTTP 422). Rewrite as plain "
            f"English with backtick code-refs (e.g., `` `PRIVATE_REPO_TOKEN` "
            f"secret from the caller ``).",
        )
        return 1
    return 0


def check_action(repo: str, action_path: Path) -> int:
    try:
        data = yaml.safe_load(action_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-102", f"{action_path.parent.name}/action.yml: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    findings = 0
    # Top-level description
    findings += check_description(repo, action_path, "top-level", data.get("description"))
    # Per-input descriptions
    inputs = data.get("inputs")
    if isinstance(inputs, dict):
        for name, spec in inputs.items():
            if isinstance(spec, dict):
                findings += check_description(
                    repo, action_path, f"inputs.{name}", spec.get("description")
                )
    # Per-output descriptions
    outputs = data.get("outputs")
    if isinstance(outputs, dict):
        for name, spec in outputs.items():
            if isinstance(spec, dict):
                findings += check_description(
                    repo, action_path, f"outputs.{name}", spec.get("description")
                )
    return findings


def main(repo: str, repo_root: str) -> int:
    findings = 0
    actions_dir = Path(repo_root) / ".github" / "actions"
    if not actions_dir.is_dir():
        return 0
    for action_path in sorted(actions_dir.glob("*/action.yml")):
        findings += check_action(repo, action_path)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-composite-action-descriptions.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
