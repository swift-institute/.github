#!/usr/bin/env python3
"""validate-manifest-binding.py — verify [CI-MANIFEST-BINDING] full-scope binding.

Phase B-2 follow-up of CI-REVIEW-PHASE-B-DESIGN-2026-05-14 §3 — Option α
adjudication 2026-05-14 (cross-repo Skills checkout). Full scope: checks
1 + 2 + 3 + 4.

Rule checked: [CI-MANIFEST-BINDING] — bidirectional binding between
.github/scripts/validators-manifest.yaml and the ci-cd-workflows skill's
SKILL.md.

Checks:
  1. Every `[VERIFICATION: WF <script>.py (...)]` annotation in
     Skills/ci-cd-workflows/SKILL.md cites a `<script>.py` whose basename
     appears in some manifest entry's `validator-script` field. Catches
     SKILL.md citing renamed/removed validators (skill-side drift).
  2. Every validate-*.py file existing on disk under .github/scripts/ is
     referenced by ≥1 manifest entry (non-empty validator-script). Catches
     orphan validators (script added without manifest update).
  3. For every manifest entry with `status: active` whose `rule-id`
     matches the ci-cd-workflows numeric shape `^CI-\\d+[a-z]?$` (e.g.,
     CI-040, CI-004b), the rule-id MUST appear in SKILL.md as
     `[<rule-id>]`. Catches manifest entries for rules not promoted into
     the skill (manifest-side drift).
  4. Every entry with `status: deprecated` has empty `validator-script`
     AND empty `workflow-file`. Catches ghost lint (deprecated entry left
     referencing a retired script).

Plus schema sanity: every entry is a dict with the required keys; status
is in the valid enum.

Scope decision for check 3
--------------------------
Check 3 fires only for rule-ids matching `^CI-\\d+[a-z]?$`. Aggregate
labels (`CI-MANIFEST-BINDING`, `GH-REPO-METADATA`, `MOD-PACKAGE-STRUCTURE`,
`README-PRESENCE`, `DOC-CATALOG`, `PATTERN-001`) and other-skill rules
(`GH-REPO-074`, `API-IMPL-006`, `API-NAME-009`, `PLAT-ARCH-008`, etc.)
are exempt because they would not be expected to appear in the
ci-cd-workflows SKILL.md. Their SKILL.md cross-checks belong to other
skills' future validator instances (out of scope for this binding
validator).

SKILL.md discovery
------------------
Three-step resolution, first match wins:

  1. CLI 3rd positional arg (`<skills_skill_md_path>`) — used by the
     workflow .yml after Skills checkout.
  2. `<repo_root>/SKILL.md` — used by hermetic fixtures (each fixture
     drops its own synthetic SKILL.md).
  3. `<repo_root>/../Skills/ci-cd-workflows/SKILL.md` — used by local
     workspace invocations from `swift-institute/.github`.

If none resolve, checks 1 + 3 are silently skipped (no findings emitted
on missing SKILL.md). This preserves backwards-compatibility with the
B-1 fixtures (which carry no SKILL.md) and lets developers run the
validator without a Skills checkout for partial verification.

Companion to validate-manifest-binding.yml (standalone workflow — the
only validator that does NOT thin-call validate-base.yml; reason: needs
a second cross-repo checkout for Skills). Pilot-shaped per [PROMOTE-006].
"""
from __future__ import annotations
import re
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

# `[VERIFICATION: ... ]` block content extractor; inner `WF <script>.py`
# citations are then pulled per-block. Allows multi-citation forms like
# `[VERIFICATION: WF foo.py + WF bar.py axis 3]`.
VERIFICATION_BLOCK_RE = re.compile(r"\[VERIFICATION:([^\]]+)\]")
SCRIPT_REF_RE = re.compile(r"\bWF\s+(validate-[\w-]+\.py)\b")

# Rule-id citation pattern in SKILL.md; matches `[CI-001]`, `[CI-004b]`, etc.
# Conservative: only checks the bracket-form citation (the canonical
# cross-reference shape across all swift-institute skills). Allows
# trailing lowercase letter ([CI-004b], [PATTERN-005a]) per the skill
# corpus's naming convention; leading char MUST be uppercase to exclude
# Markdown link text like `[Title](url)`.
RULE_ID_CITATION_RE = re.compile(r"\[([A-Z][A-Z0-9a-z-]+)\]")

# ci-cd-workflows skill's natural rule shape: `CI-<digits>[a-z]?`. Excludes
# aggregate/meta labels like CI-MANIFEST-BINDING and rules from sibling
# skills (GH-REPO-*, API-*, MOD-*, PLAT-ARCH-*, PATTERN-*, etc.).
CI_CD_RULE_ID_RE = re.compile(r"^CI-\d+[a-z]?$")


def discover_skill_md(repo_root: Path, override: str | None) -> Path | None:
    """Resolve Skills/ci-cd-workflows/SKILL.md per the three-step order.

    See module docstring §"SKILL.md discovery" for the resolution rules.
    Returns the first existing path, or None if none resolve.
    """
    if override:
        p = Path(override)
        return p if p.is_file() else None
    fixture_local = repo_root / "SKILL.md"
    if fixture_local.is_file():
        return fixture_local
    workspace_local = repo_root.parent / "Skills" / "ci-cd-workflows" / "SKILL.md"
    if workspace_local.is_file():
        return workspace_local
    return None


def cited_script_basenames(skill_md_text: str) -> set[str]:
    """Extract every `validate-*.py` basename cited inside `[VERIFICATION:]` blocks."""
    cited: set[str] = set()
    for m in VERIFICATION_BLOCK_RE.finditer(skill_md_text):
        block = m.group(1)
        for sm in SCRIPT_REF_RE.finditer(block):
            cited.add(sm.group(1))
    return cited


def cited_rule_ids(skill_md_text: str) -> set[str]:
    """Extract every `[<RULE-ID>]` citation present in SKILL.md."""
    return set(RULE_ID_CITATION_RE.findall(skill_md_text))


def main(repo: str, repo_root: str, skills_skill_md: str | None = None) -> int:
    """Validate validators-manifest.yaml + (optionally) SKILL.md cross-references.

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
    active_ci_rule_ids: set[str] = set()

    # Schema sanity + check 4 (deprecated entries empty) + collect referenced
    # scripts (for check 2) + collect active CI-numeric rule-ids (for check 3).
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

        # Collect active ci-cd-workflows numeric rule-ids for check 3.
        if status == "active" and CI_CD_RULE_ID_RE.match(rule_id):
            active_ci_rule_ids.add(rule_id)

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

    # Checks 1 + 3: cross-reference against Skills/ci-cd-workflows/SKILL.md.
    # Discovery per docstring §"SKILL.md discovery"; silent skip if no SKILL.md.
    skill_md_path = discover_skill_md(root, skills_skill_md)
    if skill_md_path is None:
        return findings

    try:
        skill_md_text = skill_md_path.read_text(encoding="utf-8")
    except OSError as e:
        emit(repo, RULE, f"SKILL.md read failed at {skill_md_path}: {e}")
        return findings + 1

    # Check 1: every `WF <script>.py` citation in SKILL.md must appear in the
    # manifest's referenced_scripts (basename match).
    manifest_basenames = {Path(p).name for p in referenced_scripts}
    for script_basename in sorted(cited_script_basenames(skill_md_text)):
        if script_basename not in manifest_basenames:
            emit(
                repo,
                RULE,
                f"SKILL.md cites `[VERIFICATION: WF {script_basename} ...]` but no "
                f"manifest entry has validator-script with basename {script_basename!r} "
                f"— per [CI-MANIFEST-BINDING] check 1, every Skills-side WF citation "
                f"MUST resolve to a manifest entry (prevents skill-side drift after "
                f"validator rename/removal).",
            )
            findings += 1

    # Check 3: every active ci-cd-workflows rule-id must appear in SKILL.md as
    # `[<rule-id>]`. Scope: rule-ids matching CI_CD_RULE_ID_RE (see docstring).
    skill_md_rule_ids = cited_rule_ids(skill_md_text)
    for rule_id in sorted(active_ci_rule_ids):
        if rule_id not in skill_md_rule_ids:
            emit(
                repo,
                RULE,
                f"manifest entry {rule_id!r} has status=active but rule-id is not "
                f"cited in SKILL.md as `[{rule_id}]` — per [CI-MANIFEST-BINDING] "
                f"check 3, every active ci-cd-workflows rule MUST be promoted into "
                f"the skill (prevents manifest-side drift / orphaned validators).",
            )
            findings += 1

    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(
            "usage: validate-manifest-binding.py <owner/name> <repo_root> "
            "[skills_skill_md_path]  # checks CI-MANIFEST-BINDING full scope "
            "(B-1 internal-consistency 2 + 4; B-2 Skills cross-refs 1 + 3)"
        )
    skills_arg = sys.argv[3] if len(sys.argv) >= 4 else None
    main(sys.argv[1], sys.argv[2], skills_arg)
