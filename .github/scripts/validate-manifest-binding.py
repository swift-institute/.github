#!/usr/bin/env python3
"""validate-manifest-binding.py — verify [CI-MANIFEST-BINDING] manifest
internal consistency.

Phase B-1 of CI-REVIEW-PHASE-B-DESIGN-2026-05-14 §3. Scope = checks
2 + 4 (internal consistency) per supervisor adjudication 2026-05-14.
Checks 1 + 3 (Skills cross-references) DEFERRED to Phase B-2 alongside
auth-surface design (Skills checkout + Skills-scoped App-token mint
OR sync-skills.sh-style [VERIFICATION:]-index mirror).

Rule checked: [CI-MANIFEST-BINDING] — internal consistency of
.github/scripts/validators-manifest.yaml.

B-1 checks:
  2. Every validate-*.py file existing under .github/scripts/ is
     referenced by ≥1 manifest entry (non-empty validator-script).
     Catches orphan validators (script added without manifest update).
  4. Every entry with status=deprecated has empty validator-script
     AND empty workflow-file. Catches ghost lint (deprecated entry
     left referencing a retired script).

Plus schema sanity: every entry is a dict with the required keys;
status is in the valid enum.

DEFERRED to Phase B-2 (require Skills access via deliberate auth-
surface design — see supervisor adjudication 2026-05-14):
  1. Every [VERIFICATION: WF <script>.py (...)] annotation in
     Skills/ci-cd-workflows/SKILL.md → manifest entry resolves.
  3. Every manifest status=active entry's rule-id exists in
     Skills/ci-cd-workflows/SKILL.md.

Companion to validate-manifest-binding.yml (thin caller of
validate-base.yml). Pilot-shaped per [PROMOTE-006].
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

REQUIRED_KEYS = {
    "rule-id",
    "validator-script",
    "workflow-file",
    "status",
    "self-firing",
    "discovery-mode",
    "rule-id-regex",
}
VALID_STATUSES = {"active", "deferred", "deprecated"}

RULE = "CI-MANIFEST-BINDING"


def main(repo: str, repo_root: str) -> int:
    """Validate validators-manifest.yaml internal consistency. Returns
    count of findings emitted."""
    yaml = require_yaml()
    root = Path(repo_root)
    manifest_path = root / ".github" / "scripts" / "validators-manifest.yaml"
    if not manifest_path.is_file():
        emit(
            repo,
            RULE,
            "manifest missing: .github/scripts/validators-manifest.yaml MUST exist "
            "per [CI-MANIFEST-BINDING] (single source-of-truth for rule-ID ↔ "
            "validator-script binding).",
        )
        return 1

    try:
        doc = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, RULE, f"manifest YAML parse failed: {e}")
        return 1

    if not isinstance(doc, dict):
        emit(repo, RULE, "manifest top-level MUST be a mapping with a 'validators:' key.")
        return 1

    entries = doc.get("validators")
    if not isinstance(entries, list):
        emit(repo, RULE, "manifest MUST contain a 'validators:' list at top level.")
        return 1

    findings = 0
    referenced_scripts: set[str] = set()

    # Schema sanity + check 4 (deprecated entries empty) + collect referenced scripts.
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            emit(repo, RULE, f"entry #{idx}: not a mapping (got {type(entry).__name__}).")
            findings += 1
            continue

        missing = REQUIRED_KEYS - set(entry.keys())
        if missing:
            rid = entry.get("rule-id", f"#{idx}")
            emit(
                repo,
                RULE,
                f"entry {rid!r}: missing required keys {sorted(missing)} — every "
                f"manifest entry MUST carry the full schema per "
                f"CI-REVIEW-PHASE-B-DESIGN §3.",
            )
            findings += 1
            continue

        rule_id = entry["rule-id"]
        status = entry["status"]

        if status not in VALID_STATUSES:
            emit(
                repo,
                RULE,
                f"entry {rule_id!r}: invalid status {status!r} — must be one of "
                f"{sorted(VALID_STATUSES)} per [CI-MANIFEST-BINDING].",
            )
            findings += 1
            continue

        # Check 4: deprecated entries MUST have empty validator-script + workflow-file.
        if status == "deprecated":
            if entry["validator-script"]:
                emit(
                    repo,
                    RULE,
                    f"entry {rule_id!r}: status=deprecated but validator-script is "
                    f"non-empty ({entry['validator-script']!r}) — deprecated entries "
                    f"MUST clear validator-script per [CI-MANIFEST-BINDING] check 4 "
                    f"(prevents ghost lint via stale script reference).",
                )
                findings += 1
            if entry["workflow-file"]:
                emit(
                    repo,
                    RULE,
                    f"entry {rule_id!r}: status=deprecated but workflow-file is "
                    f"non-empty ({entry['workflow-file']!r}) — deprecated entries "
                    f"MUST clear workflow-file per [CI-MANIFEST-BINDING] check 4.",
                )
                findings += 1

        # Collect referenced scripts for check 2 (all non-empty paths, any status).
        # A non-empty deprecated path is already flagged by check 4 above; counting
        # it here avoids double-firing check 2 on the same defect.
        script = entry.get("validator-script", "")
        if script:
            referenced_scripts.add(script)

    # Check 2: every .github/scripts/validate-*.py existing on disk is referenced.
    scripts_dir = root / ".github" / "scripts"
    if scripts_dir.is_dir():
        for path in sorted(scripts_dir.glob("validate-*.py")):
            relative = f".github/scripts/{path.name}"
            if relative not in referenced_scripts:
                emit(
                    repo,
                    RULE,
                    f"validator {relative!r} exists on disk but has no manifest "
                    f"entry — every active .github/scripts/validate-*.py MUST be "
                    f"referenced by ≥1 manifest entry per [CI-MANIFEST-BINDING] "
                    f"check 2 (prevents orphan validator drift).",
                )
                findings += 1

    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(
            "usage: validate-manifest-binding.py <owner/name> <repo_root>  "
            "# checks CI-MANIFEST-BINDING (B-1: internal consistency, "
            "checks 2 + 4; Skills cross-checks deferred to B-2)"
        )
    main(sys.argv[1], sys.argv[2])
