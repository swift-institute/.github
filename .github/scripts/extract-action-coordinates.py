#!/usr/bin/env python3
"""
Extract every `uses:` step-coordinate from a workflow file and classify its
ref, for the effective-runtime receipt (Task 6-01, swift-institute/.github#276).

STRUCTURAL parsing (PyYAML), never grep-over-text: an earlier draft of the
receipt step used a `uses:`-prefixed regex directly against the workflow
file's raw text and matched the literal string "uses:" inside this very
step's OWN embedded script — a self-scanning false positive, caught by
testing against real fetched data before shipping it. A `run: |` block's
contents are one opaque scalar string to a YAML parser and are never walked
for keys, so only genuine `steps[].uses` values are ever collected here.

Classification follows LANE-PREAMBLE's two permanent classes:
  - intra-Institute reusable workflows stay on `@main` forever, never
    pinned ([CI-030]/REPO-ACTIONS-004);
  - everything else (third-party actions, Institute composite actions)
    must already be a full 40-hex commit SHA ([CI-117]).
This is a CLASSIFICATION RECORD for the receipt, not a policy check —
validate-composite-action-pins.py and validate-branch-pins.py remain the
actual enforcement; this only states what one exact revision's bytes
contained.

Usage:
  python3 .github/scripts/extract-action-coordinates.py <workflow-file>
Outputs a JSON array of {uses, ref, classification} to stdout, sorted by
`uses` for stable output.
"""

from __future__ import annotations

import json
import re
import sys

import yaml

FULL_SHA_RE = re.compile(r"[0-9a-f]{40}")


def extract(document: dict) -> list[dict]:
    seen: set[str] = set()
    for job in (document.get("jobs") or {}).values():
        # A job can itself BE a reusable-workflow call (`uses:` at the job
        # level, no `steps:` at all — this file's six local
        # `./.github/workflows/lint-*.yml` callers are exactly this shape)
        # as well as/instead of having `steps[].uses` entries. Both are
        # genuine `uses:` coordinates and both are collected.
        job_uses = job.get("uses")
        if job_uses:
            seen.add(job_uses)
        for step in job.get("steps", []) or []:
            uses = step.get("uses")
            if uses:
                seen.add(uses)

    entries = []
    for uses in sorted(seen):
        ref = uses.split("@", 1)[1] if "@" in uses else ""
        if uses.startswith("./") and ref == "":
            # A local `./.github/workflows/<file>.yml` reusable-workflow
            # call carries no `@ref` at all — GitHub resolves it to the
            # SAME commit as the calling workflow by construction, so it is
            # exactly as deterministic as the file it appears in, without
            # needing (or being able to carry) an explicit pin.
            classification = "local-reusable-workflow"
        elif ref == "main":
            classification = "reusable-workflow-floating-main"
        elif FULL_SHA_RE.fullmatch(ref):
            classification = "identity-pinned"
        else:
            classification = "unpinnable-recorded"
        entries.append({"uses": uses, "ref": ref, "classification": classification})
    return entries


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: extract-action-coordinates.py <workflow-file>", file=sys.stderr)
        return 2
    with open(argv[0], encoding="utf-8") as f:
        document = yaml.safe_load(f)
    json.dump(extract(document), sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
