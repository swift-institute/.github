#!/usr/bin/env python3
"""validate-visibility-gate.py — verify [CI-032] public/private visibility
gate on every job in every workflow_call reusable.

Pilot 13 of `/promote-rule` (2026-05-14) — companion to
validate-visibility-gate.yml.

Single-repo multi-file integrity check sub-shape, distinct from:
  - single-target (validate-ci-matrix.py — one canonical file in one repo)
  - per-package iteration (validate-thin-callers.py — many repos, one file each)

Target: every `*.yml` / `*.yaml` file under `<repo_root>/.github/workflows/`
that declares `on.workflow_call:`. Schedule/dispatch-only workflows are
out of scope (no consumer-callable surface; no private-repo concern).

Rules checked:
  [CI-032]  Every job in every intra-Institute reusable workflow MUST carry
            `if: ${{ !github.event.repository.private }}` at the job level.
            Gate may be simple (`if: ${{ !github.event.repository.private }}`)
            or compound (`if: ${{ <prefix> && !github.event.repository.private
            && <suffix> }}`). Detection: substring `!github.event.repository.private`
            anywhere in the job's `if:` value.

  Carve-outs:
    - Jobs with `if: false` are explicitly disabled — skipped.
    - Workflows whose `on:` does NOT include `workflow_call:` are out of
      scope (scheduled/dispatch-only orchestrators have no consumer surface).
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

GATE_SUBSTRING = "!github.event.repository.private"


def get_on_block(data: dict):
    """Retrieve the `on:` block. PyYAML 1.1 parses bare `on` as boolean True;
    YAML 1.2 keeps it as the string "on". Handle both."""
    if True in data:
        return data[True]
    return data.get("on")


def is_workflow_call(on_block) -> bool:
    """Return True if the workflow declares a `workflow_call:` trigger."""
    if isinstance(on_block, str):
        return on_block == "workflow_call"
    if isinstance(on_block, list):
        return "workflow_call" in on_block
    if isinstance(on_block, dict):
        return "workflow_call" in on_block
    return False


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every job in a workflow_call workflow has the visibility gate.

    Returns count of findings.
    """
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-032", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    on_block = get_on_block(data)
    if not is_workflow_call(on_block):
        return 0  # not a reusable workflow — out of scope
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return 0
    findings = 0
    for job_name, job_data in jobs.items():
        if not isinstance(job_data, dict):
            continue
        if_clause = job_data.get("if")
        # `if: false` parses as Python bool False; treat as explicit disable.
        if if_clause is False:
            continue
        if_str = str(if_clause) if if_clause is not None else ""
        # String form of disable (rare but possible).
        if if_str.strip().lower() == "false":
            continue
        if GATE_SUBSTRING not in if_str:
            emit(
                repo,
                "CI-032",
                f"{wf_path.name}: job {job_name!r} missing visibility gate "
                f"per [CI-032] — `if:` must contain "
                f"`{GATE_SUBSTRING}` (simple or compound form); "
                f"got if={if_str!r}",
            )
            findings += 1
    return findings


def main(repo: str, repo_root: str) -> int:
    """Validate every workflow_call workflow under <repo_root>/.github/workflows/."""
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
        sys.exit("usage: validate-visibility-gate.py <owner/name> <repo_root>")
    sys.exit(0 if main(sys.argv[1], sys.argv[2]) == 0 else 0)
