#!/usr/bin/env python3
"""validate-ci-matrix.py — verify [CI-010] universal CI matrix shape + [CI-099] windows gating.

Pilot 10 of `/promote-rule` (2026-05-14) — companion to validate-ci-matrix.yml.
Pilot 20 (2026-05-14) extended with [CI-099] windows-release gating-posture check
(compose-in-script per the shared single-target canonical-file parse path).

Centralized-config integrity check: target is a single file
(`swift-institute/.github/.github/workflows/swift-ci.yml`) rather than a
per-package repo tree. Distinct shape from validate-package-shape.py /
validate-thin-callers.py (both of which iterate per-repo).

Rules checked:
  [CI-010]  The universal CI matrix MUST consist of exactly four jobs with
            specific names and shapes:
              - macos-release   : macOS runner   + Swift 6.3, debug
              - linux-release   : Ubuntu runner  + Swift 6.3, release
              - linux-nightly   : Ubuntu runner  + Swift 6.4-dev nightly,
                                  continue-on-error: true
              - windows-release : Windows runner + Swift 6.3, release

  [CI-099]  The `windows-release` job MUST stay gating — `continue-on-error: true`
            is forbidden. Windows is a first-class target platform; advisory-
            flipping would hide source-level bugs (`#if os(Windows)` divergence,
            source incompatibilities). The contrast with linux-nightly is
            semantic: nightly is toolchain-instability noise, Windows release
            is a target shipped to.

  Quality-gate jobs (format, lint, swift-linter, etc.) are per [CI-002]
  ecosystem-wide gates and are out of these rules' scope. The checks
  assert the four matrix jobs ARE present with the right runner-class
  shape and posture; they do NOT enumerate all jobs.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

REQUIRED_JOBS = ("macos-release", "linux-release", "linux-nightly", "windows-release")


def check_runner(repo: str, job_name: str, job_data: dict, expected: str) -> int:
    runs_on = str(job_data.get("runs-on", ""))
    if expected not in runs_on.lower():
        emit(
            repo,
            "CI-010",
            f"{job_name}: runs-on must reference a {expected} runner per [CI-010]; "
            f"got {runs_on!r}",
        )
        return 1
    return 0


CANONICAL_UNIVERSAL_REPO = "swift-institute/.github"


def main(repo: str, repo_root: str) -> int:
    """Validate the canonical universal swift-ci.yml under repo_root.

    Scope: ONLY the canonical universal reusable at
    `swift-institute/.github/.github/workflows/swift-ci.yml`. Layer-wrapper
    repos (swift-primitives/.github, swift-standards/.github,
    swift-foundations/.github) host their OWN swift-ci.yml with different
    intentional shapes (layer-specific jobs that `uses:` into the
    universal); they are OUT OF SCOPE for this validator's [CI-010]
    universal-matrix-shape check per [CI-002] (universal owns matrix;
    layer wrappers add layer-specific jobs).

    Repo-scope gate: the validator returns 0 (silent) unless `repo`
    matches the canonical universal repo identifier. The production
    workflow `validate-ci-matrix.yml` defaults `inputs.repo` to the
    canonical repo, but the script-level gate prevents false-positive
    findings if the validator is ever invoked against a layer wrapper
    (test invocation, misconfigured dispatch, etc.).
    """
    # Fixture carve-out: test fixtures pass repo arg `swift-institute-test/<dir>`
    # — accept any `*-test/...` repo arg as in-scope so fixtures don't need a
    # marker file. Production targets the canonical repo only.
    is_canonical = (repo == CANONICAL_UNIVERSAL_REPO)
    is_test = "-test/" in repo
    if not (is_canonical or is_test):
        return 0
    findings = 0
    wf = Path(repo_root) / ".github" / "workflows" / "swift-ci.yml"
    if not wf.is_file():
        # Repo does not host swift-ci.yml — out of scope for this validator.
        return 0
    try:
        data = yaml.safe_load(wf.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-010", f"YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        emit(repo, "CI-010", "workflow YAML root is not a mapping")
        return 1
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        emit(repo, "CI-010", "workflow has no jobs: block")
        return 1
    # Presence check: each of the four required jobs MUST appear.
    for name in REQUIRED_JOBS:
        if name not in jobs:
            emit(
                repo,
                "CI-010",
                f"required matrix job {name!r} missing from jobs: block per [CI-010]",
            )
            findings += 1
    # Shape check: runner OS class for each present job.
    expected_runners = {
        "macos-release": "macos",
        "linux-release": "ubuntu",
        "linux-nightly": "ubuntu",
        "windows-release": "windows",
    }
    for name, expected in expected_runners.items():
        job = jobs.get(name)
        if isinstance(job, dict):
            findings += check_runner(repo, name, job, expected)
    # Nightly MUST be tolerant to failure.
    nightly = jobs.get("linux-nightly")
    if isinstance(nightly, dict) and nightly.get("continue-on-error") is not True:
        emit(
            repo,
            "CI-010",
            "linux-nightly MUST set `continue-on-error: true` per [CI-010] — "
            "nightly toolchain failures are tolerated and should not gate CI",
        )
        findings += 1
    # Windows-release MUST stay gating (the inverse posture of linux-nightly).
    # Per [CI-099], advisory-flipping windows-release would hide source-level
    # bugs (`#if os(Windows)` divergence, source incompatibilities). Windows
    # is a first-class target platform; visibility outweighs upstream noise.
    windows = jobs.get("windows-release")
    if isinstance(windows, dict) and windows.get("continue-on-error") is True:
        emit(
            repo,
            "CI-099",
            "windows-release MUST stay gating per [CI-099] — "
            "`continue-on-error: true` is forbidden on this job. Windows is "
            "a first-class target platform; advisory-flipping would hide "
            "source-level bugs (`#if os(Windows)` divergence, source "
            "incompatibilities). The contrast with linux-nightly's posture "
            "is intentional: nightly is toolchain-instability noise, Windows "
            "release is a target shipped to. If a Windows compiler crash "
            "blocks main, file upstream and wait for a compiler fix; do NOT "
            "weaken the gate.",
        )
        findings += 1
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-ci-matrix.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
