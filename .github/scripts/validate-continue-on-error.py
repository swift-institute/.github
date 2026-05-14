#!/usr/bin/env python3
"""validate-continue-on-error.py — verify [CI-105] continue-on-error invariant.

Pilot 19 of `/promote-rule` (2026-05-14) — companion to validate-continue-on-error.yml.

Single-repo multi-file integrity check sub-shape (same shape as
validate-visibility-gate.py / validate-cache-policy.py / validate-harden-runner.py
/ validate-binary-install-checksum.py from pilots 13/14/15/18).

Rules checked:
  [CI-105]  `continue-on-error: true` MUST NOT co-exist with `uses:` at the
            same job level. GitHub Actions parser rejects this shape with
            `Unexpected value 'continue-on-error'` at workflow-load time,
            causing `startup_failure` across the entire chain.

  The rule is structural: `continue-on-error` is valid at (a) regular job
  level (job with `runs-on:` + `steps:`) and (b) individual step level. It
  is INVALID at workflow_call'd job level (job with `uses:` to another
  workflow). The validator fires when both keys co-exist at job level.

  Step-level `continue-on-error` (e.g., on `actions/download-artifact@v4`)
  is out of scope — the validator inspects job-level keys only, not the
  inside of `steps:` arrays.

  No file-level carve-outs. [CI-105] applies to every workflow file
  regardless of trigger shape — including reusables themselves, where a
  `uses:` job nested inside a `workflow_call:`-triggered workflow is still
  a workflow_call'd job from Actions' POV.

Detection shape: PyYAML walk; for each job in `jobs:`, check whether
`continue-on-error` is True AND `uses` is non-empty at the job level.
Both keys are top-level job properties in canonical YAML; no shell-content
parsing or indentation tracking needed.

Provenance: 2026-05-05 commit `33f638b` shipped `continue-on-error: true`
on a workflow_call'd job and broke every consumer CI's startup; fix
`b5d8445` reverted. Rule encodes regression-prevention against re-introduction.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()


def has_truthy_continue_on_error(job_data: dict) -> bool:
    """True if the job declares `continue-on-error: true` at job level.

    Per [CI-105]'s Statement, only the `: true` value is in scope.
    GitHub Actions also rejects `continue-on-error: false` on workflow_call'd
    jobs structurally, but the rule's literal Statement scopes to `: true`.
    Broader detection is a Statement-amendment candidate per [SKILL-LIFE-003].
    """
    value = job_data.get("continue-on-error")
    # PyYAML parses `true` as Python True; some workflows use the string "true"
    # under expression contexts (`continue-on-error: ${{ env.X }}` resolves at
    # runtime). Conservative reading: fire on Python True or the literal "true".
    if value is True:
        return True
    if isinstance(value, str) and value.strip().lower() == "true":
        return True
    return False


def job_uses_reusable(job_data: dict) -> bool:
    """True if the job delegates to a reusable workflow via job-level `uses:`."""
    uses = job_data.get("uses")
    return isinstance(uses, str) and bool(uses.strip())


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every job in the workflow against [CI-105]."""
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-105", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return 0
    findings = 0
    for job_name, job_data in jobs.items():
        if not isinstance(job_data, dict):
            continue
        if not job_uses_reusable(job_data):
            continue  # not a workflow_call'd job; CI-105 doesn't apply
        if has_truthy_continue_on_error(job_data):
            emit(
                repo,
                "CI-105",
                f"{wf_path.name}: job {job_name!r} has BOTH "
                f"`continue-on-error: true` AND `uses: <reusable>` at the "
                f"same job level — per [CI-105] this co-presence is "
                f"forbidden. GitHub Actions parser rejects the shape with "
                f"`Unexpected value 'continue-on-error'`, causing "
                f"`startup_failure` across the entire call chain. Replace "
                f"with the `inputs.advisory: bool` pattern: declare "
                f"`inputs.advisory` on the called workflow and gate the "
                f"step-level `exit` on `inputs.advisory != 'true'`. See "
                f"`swift-institute/Research/centralized-swift-ci-and-spine-"
                f"gate.md` §3.5.1.",
            )
            findings += 1
    return findings


def main(repo: str, repo_root: str) -> int:
    """Validate every workflow under <repo_root>/.github/workflows/."""
    findings = 0
    workflows_dir = Path(repo_root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return 0
    targets = sorted(list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml")))
    for wf in targets:
        findings += check_workflow(repo, wf)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-continue-on-error.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
