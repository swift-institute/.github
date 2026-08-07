#!/usr/bin/env python3
# RETAINED (F16 residual sweep, swift-institute/.github#404): its Swift owner
# `CI.Validation.ManifestBinding` is live and registered, but
# validate-manifest-binding.yml is a BESPOKE workflow (self-validation +
# cross-repo sweep legs) that still invokes this file unconditionally
# (`python3 "$VALIDATOR"`) rather than through validate-base.yml's
# registry-driven dispatch. The cutover did not reach it. Deletion gates on
# repointing that workflow; until then this file is the live validator.
"""validate-manifest-binding.py — verify [CI-MANIFEST-BINDING] internal-consistency binding.

Phase B-1 of CI-REVIEW-PHASE-B-DESIGN-2026-05-14 §3 (checks 2 + 4);
check 5 added 2026-05-14 (Step 3 post-arc closure) to catch the
named-targets-not-state-targets gap surfaced by the CI-090/CI-097
self-firing flip → uncomment cascade.

Rule checked: [CI-MANIFEST-BINDING] — internal consistency of
.github/scripts/validators-manifest.yaml (the single source-of-truth
for rule-ID ↔ validator-script ↔ workflow-file binding).

Checks:
  2. Every validate-*.py file existing on disk under .github/scripts/ is
     referenced by ≥1 manifest entry (non-empty validator-script). Catches
     orphan validators (script added without manifest update).
  4. Every entry with `status: deprecated` has empty `validator-script`
     AND empty `workflow-file`. Catches ghost lint (deprecated entry left
     referencing a retired script).
  5. For every manifest entry with `status: active` AND
     `self-firing: active` AND non-empty `workflow-file`, the workflow
     file MUST exist on disk AND its top-level `on:` block MUST contain
     both `push:` and `pull_request:` triggers. Catches the manifest-
     says-active-but-workflow-is-workflow_call-only failure mode that hid
     CI-090/CI-097 from flip commit e0a9155 until uncomment commit
     8babe6a landed (2026-05-14). Entries with empty `workflow-file` are
     orchestrator-embedded (e.g., fired from a cron sweeper) and are
     exempt from check 5.

Plus schema sanity: every entry is a dict with the required keys; status
is in the valid enum.

Retired: Phase B-2 (checks 1 + 3 — cross-reference against the
Skills/ci-cd-workflows skill's `[VERIFICATION: WF ...]` and `[CI-XXX]`
bracket citations, plus the SKILL.md discovery and cross-repo Skills
checkout that fed them). Retired by principal ruling on
swift-institute/.github#229 (comment 5166115277, 2026-08-03): the
2026-07-28 Skills-corpus rebuild ("Rebuild the skill corpus as nine flat
skills") deliberately dropped every bracket-form citation the corpus
carried, so a check enforcing that convention is dead weight — and the
empirically confirmed alternative (pointing SKILL.md discovery at the
corpus's new location) would flip ~18 active CI-* manifest entries
permanently red, since none can ever be cited under the new prose-only
corpus. Any future workflow↔skill cross-reference validation is a fresh
design with its own record, not a revival of this shape.

Companion to validate-manifest-binding.yml. The workflow's Skills
checkout, App-token scope, and SKILLS_SKILL_MD plumbing were removed in
the same change as this retirement — nothing in this script reads a
Skills checkout anymore.
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


def workflow_on_trigger_keys(wf_data: dict) -> set[str]:
    """Return the set of top-level trigger keys from a workflow's `on:` block.

    PyYAML YAML 1.1 quirk: the bareword `on` parses as Python boolean `True`
    (YAML 1.1 booleans include on/off/yes/no). The `on:` mapping therefore
    lives at `wf_data[True]`, not `wf_data["on"]`. The `or wf_data.get(True)`
    fallback recovers this case; mirrors the pattern in
    validate_lib.parse_on_block(). Omitting this fallback false-positives
    check 5 on every workflow.

    Handles three `on:` shapes:
      - map form:    on: {push: ..., pull_request: ...}  → set of map keys
      - list form:   on: [push, pull_request]            → set of list items
      - scalar form: on: push                            → {"push"}
    Returns an empty set if `on:` is absent or another shape.
    """
    on_block = wf_data.get("on")
    if on_block is None:
        on_block = wf_data.get(True)
    if isinstance(on_block, dict):
        return set(on_block.keys())
    if isinstance(on_block, list):
        return set(on_block)
    if isinstance(on_block, str):
        return {on_block}
    return set()


def main(repo: str, repo_root: str) -> int:
    """Validate validators-manifest.yaml's internal consistency.

    Returns count of findings emitted.
    """
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

    # Schema sanity + check 4 (deprecated entries empty) + check 5 (self-firing
    # active entries resolve to a triggering workflow) + collect referenced
    # scripts (for check 2).
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

        # Check 5: self-firing:active entries MUST have a workflow with push +
        # pull_request triggers at top level. Skips deferred/deprecated entries
        # and orchestrator-embedded entries (empty workflow-file).
        if status == "active" and entry.get("self-firing") == "active":
            workflow_file = entry.get("workflow-file", "")
            if workflow_file:
                wf_path = root / workflow_file
                if not wf_path.is_file():
                    emit(
                        repo,
                        RULE,
                        f"entry {rule_id!r}: declared self-firing: active but "
                        f"workflow-file {workflow_file!r} does not exist on disk — "
                        f"per [CI-MANIFEST-BINDING] check 5, every active "
                        f"self-firing entry MUST resolve to an on-disk workflow.",
                    )
                    findings += 1
                else:
                    try:
                        wf_data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
                    except Exception as e:
                        emit(
                            repo,
                            RULE,
                            f"entry {rule_id!r}: workflow-file {workflow_file!r} "
                            f"YAML parse failed: {e}",
                        )
                        findings += 1
                    else:
                        if isinstance(wf_data, dict):
                            triggers = workflow_on_trigger_keys(wf_data)
                            missing_triggers = {"push", "pull_request"} - triggers
                            if missing_triggers:
                                emit(
                                    repo,
                                    RULE,
                                    f"entry {rule_id!r}: declared self-firing: "
                                    f"active in manifest but workflow-file "
                                    f"{workflow_file!r} missing trigger(s) "
                                    f"{sorted(missing_triggers)} at top level of "
                                    f"`on:` (has: {sorted(triggers)}) — per "
                                    f"[CI-MANIFEST-BINDING] check 5 (catches the "
                                    f"manifest-says-active-but-workflow-is-"
                                    f"workflow_call-only failure mode).",
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
            "usage: validate-manifest-binding.py <owner/name> <repo_root>  # "
            "checks CI-MANIFEST-BINDING internal consistency (2 + 4 + 5); "
            "Phase B-2 Skills cross-refs (1 + 3) retired per #229"
        )
    main(sys.argv[1], sys.argv[2])
