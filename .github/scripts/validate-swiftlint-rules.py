#!/usr/bin/env python3
"""validate-swiftlint-rules.py — verify [CI-100] SwiftLint Tier 1 rule exclusions.

Pilot 22 of `/promote-rule` (2026-05-14) — companion to validate-swiftlint-rules.yml.

Centralized-config integrity check sub-shape (single canonical file).

Rules checked:
  [CI-100]  The canonical Tier 1 `.swiftlint.yml` at `<repo_root>/.swiftlint.yml`
            MUST NOT enable the built-in opt-in rule `toggle_bool`. User-
            direction rule: `x = !x` is preferred over `x.toggle()`.

  Detection: parse `<repo_root>/.swiftlint.yml` as YAML; if it contains
  `toggle_bool` in the `opt_in_rules:` list (or `analyzer_rules:`,
  `enabled_rules:` equivalents), fire. The standard way to enable an opt-in
  rule is to include it in `opt_in_rules:`; absence from that list keeps it
  off.

  No file-level carve-outs. The validator targets a single file (the
  canonical Tier 1 config); per-package `.swiftlint.yml` files are out of
  scope per [CI-057] (per-package config autonomy).

Detection shape: PyYAML walk; check a small set of rule-list keys for the
forbidden rule name.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

# SwiftLint config keys that ENABLE a rule (presence = rule is active).
# `disabled_rules:` and `only_rules:` are exclusion/whitelist; not in scope.
ENABLE_KEYS = ("opt_in_rules", "analyzer_rules", "enabled_rules")

FORBIDDEN_RULE = "toggle_bool"


def check_swiftlint_yml(repo: str, path: Path) -> int:
    """Check that the .swiftlint.yml does not enable the forbidden rule."""
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-100", f".swiftlint.yml: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    findings = 0
    for key in ENABLE_KEYS:
        rules = data.get(key)
        if isinstance(rules, list) and FORBIDDEN_RULE in rules:
            emit(
                repo,
                "CI-100",
                f".swiftlint.yml has `{FORBIDDEN_RULE}` in `{key}:` — per "
                f"[CI-100] this SwiftLint opt-in rule MUST NOT be enabled in "
                f"the canonical Tier 1 configuration. User direction "
                f"2026-05-05: `x = !x` is preferred over `x.toggle()`. "
                f"Remove the entry; if a comment marker is desired, see "
                f"swift-institute/.github/.swiftlint.yml line 66 for the "
                f"canonical comment shape.",
            )
            findings += 1
    return findings


def main(repo: str, repo_root: str) -> int:
    """Validate <repo_root>/.swiftlint.yml against [CI-100]."""
    path = Path(repo_root) / ".swiftlint.yml"
    if not path.is_file():
        return 0  # Repo doesn't host the canonical Tier 1 config; out of scope.
    return check_swiftlint_yml(repo, path)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-swiftlint-rules.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
