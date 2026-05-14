#!/usr/bin/env python3
"""validate-embedded-job.py — verify [CI-021] embedded-job continue-on-error posture.

Pilot 23 of `/promote-rule` (2026-05-14) — companion to validate-embedded-job.yml.

Centralized-config integrity check sub-shape (single canonical file in any
layer-wrapper-host repo whose `swift-ci.yml` defines an `embedded` job).

Rules checked:
  [CI-021]  In any `<repo_root>/.github/workflows/swift-ci.yml` that declares a
            job named `embedded`, that job MUST carry `continue-on-error: true`
            while Swift 6.4-dev nightly is the development branch. Sunsets via
            skill amendment when 6.4 stabilizes.

  Detection: parse `<repo_root>/.github/workflows/swift-ci.yml`; if it has
  `jobs.embedded`, assert that job's `continue-on-error` is True. If no
  embedded job exists, the validator is silent (out of scope for that repo
  — typically the universal `swift-institute/.github` wrapper).

  Currently the only repo with an `embedded` job is `swift-primitives/.github`
  (the L1 wrapper). Future layer wrappers could add the same job; this
  validator is structurally general.

  No file-level carve-outs.

Detection shape: PyYAML walk; single-target single-job check.
"""
from __future__ import annotations
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()


def main(repo: str, repo_root: str) -> int:
    """Validate <repo_root>/.github/workflows/swift-ci.yml's embedded job."""
    wf = Path(repo_root) / ".github" / "workflows" / "swift-ci.yml"
    if not wf.is_file():
        return 0  # repo doesn't host swift-ci.yml; out of scope
    try:
        data = yaml.safe_load(wf.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-021", f"swift-ci.yml: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return 0
    embedded = jobs.get("embedded")
    if not isinstance(embedded, dict):
        return 0  # no embedded job in this swift-ci.yml — out of scope
    if embedded.get("continue-on-error") is not True:
        emit(
            repo,
            "CI-021",
            f"swift-ci.yml: job 'embedded' MUST set `continue-on-error: true` "
            f"per [CI-021] — the embedded build runs against Swift 6.4-dev "
            f"nightly toolchain whose instability is expected; advisory "
            f"posture absorbs toolchain-noise without gating consumer CI. "
            f"Sunsets via skill amendment when 6.4 stabilizes (until then, "
            f"the gate stays advisory).",
        )
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-embedded-job.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
