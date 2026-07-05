#!/usr/bin/env python3
"""detect-startup-failures.py — flag GitHub Actions runs that concluded `startup_failure`.

A `startup_failure` means a workflow never started — bad YAML, a missing
reusable, a `workflow_call` permissions/chain mismatch ([CI-105]/[CI-106]), or a
`permissions: {}` on a reusable ([CI-097]). It is invisible to every per-job
gate because NO job runs: `conclusion: startup_failure`, `jobs: []`, and no
fetchable logs. This probe scans recent Actions runs across the shared `.github`
repos and fails (exit 1) if any run concluded `startup_failure`, so the class is
surfaced weekly rather than lurking until the next scheduled firing.

Detection is a pure function (`find_startup_failures`) so it is unit-testable
without hitting the API; `.github/scripts/tests/test-detect-startup-failures.py`
proves it flags synthetic data and passes on clean data. A `--selftest` mode
runs the same function-level assertions inline.

Input: a JSON file argument, or `-` / no argument for stdin. The payload is
shaped like the GitHub REST `GET /repos/{owner}/{repo}/actions/runs` response —
either the full object (with a `workflow_runs` array) or a bare array of run
objects. Each run carries at least `conclusion`, and optionally `name`, `id`,
`html_url`, `created_at`.

Exit codes:
  0 — no `startup_failure` runs found (clean)
  1 — at least one `startup_failure` run found (flagged)
  2 — usage / input error
"""
from __future__ import annotations

import json
import sys
from typing import Any

STARTUP_FAILURE = "startup_failure"


def extract_runs(data: Any) -> list[dict]:
    """Normalize a GitHub Actions runs payload to a list of run dicts.

    Accepts the full API object (`{"workflow_runs": [...]}`) or a bare list.
    Any other shape yields an empty list (no runs to inspect).
    """
    if isinstance(data, dict):
        runs = data.get("workflow_runs")
        return [r for r in runs if isinstance(r, dict)] if isinstance(runs, list) else []
    if isinstance(data, list):
        return [r for r in data if isinstance(r, dict)]
    return []


def find_startup_failures(runs: list[dict]) -> list[dict]:
    """Return the subset of runs whose `conclusion` is exactly `startup_failure`.

    Pure function — the testable core. `startup_failure` is GitHub's own
    `conclusion` for a run that aborted before any job started: such a run has an
    empty `jobs` array and no fetchable logs. That conclusion is the single
    signal checked here — there is no separate per-run jobs-API inspection.
    `conclusion` is `None` for in-progress runs and a non-matching string for
    every other terminal state, so only the exact `startup_failure` value is
    flagged.
    """
    return [r for r in runs if isinstance(r, dict) and r.get("conclusion") == STARTUP_FAILURE]


def _selftest() -> int:
    dirty = [
        {"conclusion": "success", "name": "swift-ci", "id": 1},
        {"conclusion": STARTUP_FAILURE, "name": "swift-docs", "id": 2, "html_url": "u"},
    ]
    clean = [
        {"conclusion": "success", "name": "a", "id": 1},
        {"conclusion": "failure", "name": "b", "id": 2},
        {"conclusion": None, "name": "c", "id": 3},
    ]
    assert len(find_startup_failures(dirty)) == 1, "must flag the one startup_failure"
    assert find_startup_failures(clean) == [], "clean data must not flag"
    # API-object shape is unwrapped by extract_runs.
    assert len(find_startup_failures(extract_runs({"workflow_runs": dirty}))) == 1
    assert find_startup_failures(extract_runs({"workflow_runs": clean})) == []
    print("selftest OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "--selftest":
        return _selftest()

    if len(argv) >= 2 and argv[1] != "-":
        try:
            text = open(argv[1], encoding="utf-8").read()
        except OSError as e:
            print(f"# error: cannot read {argv[1]}: {e}", file=sys.stderr)
            return 2
    else:
        text = sys.stdin.read()

    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"# error: invalid JSON input: {e}", file=sys.stderr)
        return 2

    runs = extract_runs(data)
    flagged = find_startup_failures(runs)
    if not flagged:
        print(f"clean: 0 startup_failure runs in {len(runs)} recent run(s).")
        return 0
    print(f"FLAGGED: {len(flagged)} startup_failure run(s) in {len(runs)} recent run(s):")
    for r in flagged:
        name = r.get("name", "?")
        rid = r.get("id", "?")
        url = r.get("html_url", "")
        print(f"  - {name} (run {rid}) {url}".rstrip())
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
