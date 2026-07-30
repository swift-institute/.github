#!/usr/bin/env python3
"""check-lint-validators-weekly-parity.py — fail closed on report-surface drift (#117).

`.github/workflows/lint-validators-weekly.yml`'s `report` job repeats its
scan-leg set across five hand-synchronized surfaces:

  1. the `needs:` list
  2. the skipped-detection `if:` condition
  3. the `RESULT_*` env block (on the "Build issue body" step)
  4. the per-validator aggregation pair list (the `for pair in ...` loop,
     also inside "Build issue body")
  5. the issue-body sections (the heredoc built by the same step)

Nothing previously checked that these stayed in correspondence with the
`scan-*` jobs actually defined in the workflow. It has already drifted
twice — once requiring eight hand-touched places for a new leg
(9c783b0), once shipping a leg with none of the five surfaces wired
(2cd782e, scan-gitignore) until caught by review rather than by any
check.

This script discovers every `scan-*` job from the workflow's own `jobs:`
mapping (never a hard-coded roster) and asserts, for each one, that a
correspondingly-named entry exists on all five surfaces. A `scan-*` job
added without full report wiring fails this check.

Naming contract this check assumes and enforces implicitly by
construction (a job that does not follow it will simply fail every
surface check, which is the correct fail-closed outcome):

  scan-<slug>                              job name
  RESULT_<SLUG_UPPER_SNAKE>                env var / pair-list result ref
  validate-<slug>                          issue-body section heading

Usage:
    check-lint-validators-weekly-parity.py [path/to/lint-validators-weekly.yml]

Exit 0 with no output when every scan-* job is fully wired. Exit 1 with
one TSV finding line per (job, surface) gap otherwise. Exit 2 on a
structural read/parse failure (missing file, missing `report` job,
missing "Build issue body" step, PyYAML absent) — an environment/shape
defect, not a drift finding.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

REPO = "swift-institute/.github"
RULE = "LINT-VALIDATORS-WEEKLY-DRIFT"
REPORT_JOB_NAME = "report"
BUILD_STEP_NAME = "Build issue body"

DEFAULT_PATH = ".github/workflows/lint-validators-weekly.yml"


def emit(message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{REPO}\t{RULE}\t{safe}")


def require_yaml():
    try:
        import yaml
        return yaml
    except ImportError:
        print("# error: PyYAML not installed", file=sys.stderr)
        sys.exit(2)


def slug_of(job_name: str) -> str:
    assert job_name.startswith("scan-")
    return job_name[len("scan-"):]


def result_var_of(slug: str) -> str:
    return "RESULT_" + slug.upper().replace("-", "_")


def get_scan_jobs(data: dict) -> list[str]:
    jobs = data.get("jobs") or {}
    return sorted(name for name in jobs if isinstance(name, str) and name.startswith("scan-"))


def get_report_job(data: dict) -> dict:
    jobs = data.get("jobs") or {}
    report = jobs.get(REPORT_JOB_NAME)
    if not isinstance(report, dict):
        raise LookupError(f"no '{REPORT_JOB_NAME}' job in jobs:")
    return report


def get_build_step(report: dict) -> dict:
    for step in report.get("steps") or []:
        if isinstance(step, dict) and step.get("name") == BUILD_STEP_NAME:
            return step
    raise LookupError(f"no step named '{BUILD_STEP_NAME}' in the '{REPORT_JOB_NAME}' job")


def extract_heredoc(run_text: str) -> str:
    """Return the body of the first `<<EOF ... EOF` heredoc in a run: script.

    Falls back to the whole script if no heredoc is found, so a caller
    that greps this text for a missing section still gets a real (if
    less precise) drift finding instead of a crash.
    """
    lines = run_text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if "<<EOF" in line:
            start = i + 1
            break
    if start is None:
        return run_text
    for j in range(start, len(lines)):
        if lines[j].strip() == "EOF":
            return "\n".join(lines[start:j])
    return "\n".join(lines[start:])


def check_workflow_dict(data: dict) -> list[tuple[str, str, str]]:
    """Return a list of (job, surface, message) drift findings.

    Empty list means every scan-* job discovered in `data` is wired into
    all five report surfaces.
    """
    findings: list[tuple[str, str, str]] = []

    scan_jobs = get_scan_jobs(data)
    report = get_report_job(data)
    needs = report.get("needs") or []
    if isinstance(needs, str):
        needs = [needs]
    if_str = str(report.get("if") or "")
    build_step = get_build_step(report)
    env = build_step.get("env") or {}
    run_text = str(build_step.get("run") or "")
    heredoc = extract_heredoc(run_text)

    for job in scan_jobs:
        slug = slug_of(job)
        result_var = result_var_of(slug)

        if job not in needs:
            findings.append((job, "needs", f"'{job}' is missing from the report job's needs: list"))

        if f"needs.{job}.result" not in if_str:
            findings.append((job, "if-condition",
                              f"the report job's if: condition does not reference needs.{job}.result"))

        env_value = str(env.get(result_var) or "")
        if result_var not in env:
            findings.append((job, "result-env",
                              f"'{BUILD_STEP_NAME}' env: block is missing {result_var}"))
        elif f"needs.{job}.result" not in env_value:
            findings.append((job, "result-env",
                              f"{result_var} does not reference needs.{job}.result (found: {env_value!r})"))

        pair_token = f'"{slug}:${result_var}"'
        if pair_token not in run_text:
            findings.append((job, "aggregation-pair-list",
                              f"the aggregation pair list is missing {pair_token}"))

        heading = f"### validate-{slug}"
        if heading not in heredoc:
            findings.append((job, "issue-body-section",
                              f"the issue-body heredoc is missing a '{heading}' section"))
        elif result_var not in heredoc:
            findings.append((job, "issue-body-section",
                              f"the issue-body heredoc's '{heading}' section does not reference {result_var}"))

    return findings


def main(argv: list[str]) -> int:
    yaml = require_yaml()
    path = Path(argv[1] if len(argv) > 1 else DEFAULT_PATH)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"# error: cannot read {path}: {exc}", file=sys.stderr)
        return 2
    try:
        data = yaml.safe_load(text)
    except Exception as exc:  # noqa: BLE001 - surface any parse failure as env defect
        print(f"# error: cannot parse {path} as YAML: {exc}", file=sys.stderr)
        return 2

    try:
        findings = check_workflow_dict(data)
    except LookupError as exc:
        print(f"# error: {path} does not have the expected report-job shape: {exc}", file=sys.stderr)
        return 2

    for job, surface, message in findings:
        emit(f"{surface}: {message}")

    if findings:
        print(f"::error::{len(findings)} report-surface drift finding(s) in {path}. "
              "A scan-* job defined in this workflow is not fully wired into the report "
              "job's five surfaces (needs:, if:, RESULT_* env, aggregation pair list, "
              "issue-body section). See findings above.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
