#!/usr/bin/env python3
"""validate-harden-runner.py — verify [CI-080] harden-runner audit-mode floor.

Pilot 15 of `/promote-rule` (2026-05-14) — companion to validate-harden-runner.yml.

Single-repo multi-file integrity check sub-shape (same shape as
validate-visibility-gate.py / validate-cache-policy.py from pilots 13/14).

Rules checked:
  [CI-080]  Every in-scope job in every workflow under
            <repo>/.github/workflows/ MUST install
            `step-security/harden-runner` as its FIRST step, SHA-pinned
            (`@<40-char-sha>`).

  Excluded jobs (carve-outs):
    - Pure `uses:`-only jobs (workflow_call routing): the called workflow's
      own jobs run their own harden-runner. Detected by: job has `uses:` at
      job level AND no `steps:`.
    - Conclusion-aggregator jobs: run only `jq` against `needs.*.result`; no
      network egress. Detected by job name in a known-aggregator list
      (currently: `ci-ok`).

  Two failure modes detected:
    (a) First step is not `step-security/harden-runner@*`
    (b) First step IS harden-runner but not SHA-pinned (e.g., `@v2.19.1`
        instead of `@<40-hex>` — major-tag pin defeats the integrity the
        action provides)
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

HARDEN_RUNNER_PREFIX = "step-security/harden-runner@"
SHA_PIN_RE = re.compile(r"^step-security/harden-runner@[a-f0-9]{40}$")

# Known aggregator jobs: name matches → carve-out applies.
AGGREGATOR_JOB_NAMES = frozenset({"ci-ok"})


def is_pure_uses_only_job(job_data: dict) -> bool:
    """A workflow_call routing job: `uses:` at job level, no `steps:`."""
    return "uses" in job_data and "steps" not in job_data


def is_aggregator_job(job_name: str) -> bool:
    return job_name in AGGREGATOR_JOB_NAMES


def get_first_step(job_data: dict):
    steps = job_data.get("steps")
    if not isinstance(steps, list) or not steps:
        return None
    first = steps[0]
    if not isinstance(first, dict):
        return None
    return first


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every in-scope job's first step is SHA-pinned harden-runner."""
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-080", f"{wf_path.name}: YAML parse failed: {e}")
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
        if is_pure_uses_only_job(job_data):
            continue
        if is_aggregator_job(job_name):
            continue
        first = get_first_step(job_data)
        if first is None:
            # Job has no steps and isn't pure-uses-only — odd shape; skip.
            continue
        uses = str(first.get("uses", ""))
        if not uses.startswith(HARDEN_RUNNER_PREFIX):
            emit(
                repo,
                "CI-080",
                f"{wf_path.name}: job {job_name!r} first step is not "
                f"`step-security/harden-runner@*` per [CI-080] — security "
                f"floor requires harden-runner as the first step on every "
                f"in-scope job. first step uses={uses!r}",
            )
            findings += 1
        elif not SHA_PIN_RE.match(uses):
            emit(
                repo,
                "CI-080",
                f"{wf_path.name}: job {job_name!r} harden-runner not "
                f"SHA-pinned per [CI-080] — security action MUST pin to "
                f"`@<40-char-sha>`, not a major-tag like `@v2.19.1`. "
                f"got uses={uses!r}",
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
        sys.exit("usage: validate-harden-runner.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
