#!/usr/bin/env python3
"""
Compute the effective-runtime receipt's `referenced_workflows` field from a
GitHub Actions run object (Task 6-01 reclaim, swift-institute/.github#276,
predicate 20).

Extracted from the "Emit effective-runtime receipt" step in swift-ci.yml so
this logic is independently testable. This is not a reimplementation
alongside the shell — the workflow step calls this exact script; there is
one copy of the decision.

An empty `referenced_workflows` array on the run object must never be
silently reported as measured (that would misrepresent a run whose
reusable-workflow chain GitHub did not resolve as one that resolved to
nothing) or dropped from the schema. It is recorded as `UNMEASURED` with an
explicit reason. A non-empty array is passed through verbatim as `measured`.

Usage:
  python3 .github/scripts/compute-referenced-workflows.py <run.json>
Reads the run object from the given file (as fetched from
`GET /repos/{repo}/actions/runs/{run_id}`) and prints the receipt's
`referenced_workflows` field, as JSON, to stdout.
"""

from __future__ import annotations

import json
import sys


def compute(run: dict) -> dict:
    entries = run.get("referenced_workflows") or []
    if len(entries) == 0:
        return {
            "status": "UNMEASURED",
            "reason": "run object reported zero referenced_workflows",
            "entries": [],
        }
    return {"status": "measured", "reason": None, "entries": entries}


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: compute-referenced-workflows.py <run.json>", file=sys.stderr)
        return 2
    with open(argv[0], encoding="utf-8") as f:
        run = json.load(f)
    json.dump(compute(run), sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
