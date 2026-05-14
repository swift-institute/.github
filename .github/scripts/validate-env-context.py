#!/usr/bin/env python3
"""validate-env-context.py — verify [CI-103] env-context-availability invariant.

Pilot 21 of `/promote-rule` (2026-05-14) — companion to validate-env-context.yml.

Single-repo multi-file integrity check sub-shape (same shape as
validate-visibility-gate.py / validate-cache-policy.py / validate-harden-runner.py
/ validate-binary-install-checksum.py / validate-continue-on-error.py from pilots
13/14/15/18/19).

Rules checked:
  [CI-103]  Workflow-level `env:` MUST NOT be referenced from `runs-on:` or
            `container:` fields. GitHub Actions resolves these fields BEFORE
            workflow-level `env:` is bound, producing parse-time HTTP 422.

  Detection target: per-job `runs-on:` value (string or list) and `container:`
  value (string or dict with `image:` key). The validator inspects the string
  payload for `${{ env.X }}` substring (any whitespace allowed inside the
  curly braces); other context references (`inputs.*`, `vars.*`, `matrix.*`,
  `github.*`, `secrets.*`, etc.) are permitted in these fields per the
  Actions context-availability rules and are NOT flagged.

  Two failure modes detected:
    (A) `runs-on:` references `${{ env.X }}` — including in a list-form
        `runs-on: [...]` array element.
    (B) `container:` references `${{ env.X }}` — including in dict-form
        `container.image:` (the canonical multi-key form).

  No file-level carve-outs. [CI-103] applies to every workflow file
  regardless of trigger shape; both standalone workflows and reusables can
  trigger the HTTP 422 if they reference env.* in these fields.

Detection shape: PyYAML walk; per-job structural inspection of two specific
keys at job level. The `${{ env.X }}` substring check is regex-anchored to
the GitHub Actions expression-context syntax (`\\$\\{\\{\\s*env\\.`).

Provenance: 2026-05-05 commits `ecf36e6` + `91dd8db` shipped `container:
swift:${{ env.SWIFT_VERSION }}` and broke 2 cron orchestrators with HTTP 422
at workflow load. Recovery `e9b468e` reverted to literal hardcode. Rule
encodes regression-prevention against re-introduction.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

# `${{ env.X }}` expression reference. The Actions parser tolerates any
# whitespace around the keyword and dot; conservative regex matches all
# canonical forms. Other contexts (`inputs`, `vars`, `matrix`, `github`,
# `secrets`, etc.) are out of scope per the rule body.
ENV_REF_RE = re.compile(r"\$\{\{\s*env\.\w+")


def has_env_ref(value: object) -> bool:
    """True if the value's string representation contains a `${{ env.X }}` ref.

    Handles string values directly. For list values (runs-on: array form),
    inspects each element. Returns False for other types.
    """
    if isinstance(value, str):
        return bool(ENV_REF_RE.search(value))
    if isinstance(value, list):
        return any(has_env_ref(item) for item in value)
    return False


def check_runs_on(repo: str, wf_name: str, job_name: str, runs_on: object) -> int:
    """Check [CI-103] on a job's `runs-on:` value."""
    if not has_env_ref(runs_on):
        return 0
    emit(
        repo,
        "CI-103",
        f"{wf_name}: job {job_name!r} has `runs-on:` referencing "
        f"`${{{{ env.X }}}}` — per [CI-103] workflow-level `env:` is NOT "
        f"available in `runs-on:` (Actions resolves this field before env: "
        f"binds; produces parse-time HTTP 422). Use `inputs.<name>` "
        f"(workflow_call), `vars.<name>` (org/repo level), or literal "
        f"hardcode instead.",
    )
    return 1


def check_container(repo: str, wf_name: str, job_name: str, container: object) -> int:
    """Check [CI-103] on a job's `container:` value (string or dict form)."""
    if isinstance(container, str):
        if has_env_ref(container):
            emit(
                repo,
                "CI-103",
                f"{wf_name}: job {job_name!r} has `container:` referencing "
                f"`${{{{ env.X }}}}` — per [CI-103] workflow-level `env:` is "
                f"NOT available in `container:` (same context-availability "
                f"rule as `runs-on:`; produces parse-time HTTP 422). Use "
                f"`inputs.<name>`, `vars.<name>`, or literal hardcode.",
            )
            return 1
    elif isinstance(container, dict):
        image = container.get("image")
        if has_env_ref(image):
            emit(
                repo,
                "CI-103",
                f"{wf_name}: job {job_name!r} has `container.image:` "
                f"referencing `${{{{ env.X }}}}` — per [CI-103] workflow-"
                f"level `env:` is NOT available in `container:` (dict-form "
                f"`image:` is bound at the same time as the string-form "
                f"shorthand; same HTTP 422 trigger).",
            )
            return 1
    return 0


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every job's runs-on: and container: against [CI-103]."""
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-103", f"{wf_path.name}: YAML parse failed: {e}")
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
        runs_on = job_data.get("runs-on")
        if runs_on is not None:
            findings += check_runs_on(repo, wf_path.name, job_name, runs_on)
        container = job_data.get("container")
        if container is not None:
            findings += check_container(repo, wf_path.name, job_name, container)
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
        sys.exit("usage: validate-env-context.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
