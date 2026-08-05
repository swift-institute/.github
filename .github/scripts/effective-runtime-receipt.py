#!/usr/bin/env python3
"""effective-runtime-receipt.py — pure base canonicalizer for the version-1
effective runtime receipt (TX7 receipt contract, swift-institute/.github#276
§8.9; predicates P19/P20).

Consumes the run object and paginated jobs collection the aggregate job
fetched for ITS OWN run (it never calls GitHub itself, never expands a
matrix, never evaluates workflow expressions, and never asserts a terminal
conclusion while its own run is in progress) and emits the canonical
`preterminal` base record plus its digest.

The record is an object with exactly these top-level keys:
  schemaVersion, attestationStage, baseReceiptDigest, run, subject,
  referencedWorkflows, actions, containers, linter, jobs, revisions,
  verdict, unmeasured.

Canonical bytes are UTF-8 JSON with lexicographically sorted object keys,
no insignificant whitespace, LF termination; arrays are sorted by their
declared identity key (path / coordinate / numeric job id); every digest
is lowercase SHA-256 of those bytes.

P20 control: an empty or unavailable `referenced_workflows` collection
makes the receipt `UNMEASURED` and this helper EXIT NONZERO — the empty
reusable-workflow chain is exactly the evidence gap the historical
false-success variant silently accepted, and it is never replaced by a
read of current `main`.

Usage:
  python3 .github/scripts/effective-runtime-receipt.py \
    --run-json run.json --jobs-json jobs.json \
    --planned-gating macos-release,linux-release,... \
    --subject-repository owner/name --subject-sha <40hex> \
    --subject-visibility public \
    --output effective-runtime-receipt.v1.base.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys


def canonical_bytes(record: dict) -> bytes:
    return (
        json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def digest(record: dict) -> str:
    return hashlib.sha256(canonical_bytes(record)).hexdigest()


def build_base_record(
    run: dict,
    jobs: list[dict],
    *,
    planned_gating: list[str],
    subject_repository: str,
    subject_sha: str,
    subject_visibility: str,
    strict_referenced_workflows: bool = True,
) -> tuple[dict, bool]:
    """Return (record, ok). `ok` is False when the record is UNMEASURED in a
    way the producing aggregate must fail on (P20 empty-hop control).

    `strict_referenced_workflows=False` reproduces the HISTORICAL
    false-success behavior for the mandatory negative-control test ONLY —
    production callers never pass it."""
    unmeasured: list[dict] = []

    def field(value, name, reason):
        if value is None:
            unmeasured.append({"field": name, "reason": reason})
        return value

    referenced = [
        {
            "path": r.get("path"),
            "ref": r.get("ref"),
            "sha": r.get("sha"),
        }
        for r in (run.get("referenced_workflows") or [])
    ]
    referenced.sort(key=lambda r: (r["path"] or ""))
    empty_chain = len(referenced) == 0
    if empty_chain:
        unmeasured.append(
            {
                "field": "referencedWorkflows",
                "reason": "run object exposed an empty/unavailable referenced_workflows collection; the reusable-workflow chain is unmeasured and is never replaced by a read of current main",
            }
        )

    job_rows = []
    for j in jobs:
        name = j.get("name") or ""
        # The aggregate's own-run jobs collection carries flattened names
        # ("ci-ok", "Plan (…)", "macos-release …"); mandatory/selected is
        # derived from the Plan-declared gating list by leading token.
        leading = name.split(" ", 1)[0].split(" /", 1)[0]
        mandatory = leading in planned_gating
        conclusion = j.get("conclusion")
        if conclusion is None:
            unmeasured.append(
                {
                    "field": f"jobs[{j.get('id')}].conclusion",
                    "reason": "unavailable at in-run capture (job not terminal while the aggregate observes its own run)",
                }
            )
        job_rows.append(
            {
                "id": j.get("id"),
                "name": name,
                "conclusion": conclusion,
                "selected": mandatory or conclusion not in (None, "skipped"),
                "mandatory": mandatory,
                "runnerLabels": j.get("labels") or [],
            }
        )
    job_rows.sort(key=lambda r: (r["id"] is None, r["id"]))

    run_conclusion = run.get("conclusion")
    if run_conclusion is None:
        unmeasured.append(
            {
                "field": "run.conclusion",
                "reason": "unavailable at in-run capture (the run cannot be terminal while its own aggregate job executes)",
            }
        )

    for name, reason in (
        ("actions", "selected action coordinates are not resolvable from the run/jobs objects at in-run capture; terminal resolution is collector scope"),
        ("containers", "container image digests are not resolvable from the run/jobs objects at in-run capture"),
        ("linter", "linter release/authority/checksum identity is not exposed to the aggregate at in-run capture"),
        ("revisions", "workspace/policy/fixture revisions and the effective-inventory digest await the TX1/TX3 typed adapters"),
    ):
        unmeasured.append({"field": name, "reason": reason})

    record = {
        "schemaVersion": 1,
        "attestationStage": "preterminal",
        "baseReceiptDigest": None,
        "run": {
            "repository": field(run.get("repository", {}).get("full_name"), "run.repository", "absent from run object"),
            "workflowPath": field(run.get("path"), "run.workflowPath", "absent from run object"),
            "event": field(run.get("event"), "run.event", "absent from run object"),
            "actor": field((run.get("actor") or {}).get("login"), "run.actor", "absent from run object"),
            "headRepository": field((run.get("head_repository") or {}).get("full_name"), "run.headRepository", "absent from run object"),
            "headBranch": run.get("head_branch"),
            "headSha": field(run.get("head_sha"), "run.headSha", "absent from run object"),
            "id": field(run.get("id"), "run.id", "absent from run object"),
            "attempt": field(run.get("run_attempt"), "run.attempt", "absent from run object"),
            "conclusion": run_conclusion,
        },
        "subject": {
            "repository": subject_repository,
            "sha": subject_sha,
            "visibility": subject_visibility,
        },
        "referencedWorkflows": referenced,
        "actions": [],
        "containers": [],
        "linter": None,
        "jobs": job_rows,
        "revisions": None,
        "verdict": "UNMEASURED" if empty_chain else "preterminal",
        "unmeasured": sorted(unmeasured, key=lambda u: u["field"]),
    }
    ok = (not empty_chain) or (not strict_referenced_workflows)
    if not strict_referenced_workflows and empty_chain:
        # Historical false-success shape: silently clean verdict on an
        # empty chain. Exists ONLY so the P20 negative-control test can
        # observe it fail; never reachable from the CLI.
        record["verdict"] = "preterminal"
    return record, ok


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-json", required=True)
    parser.add_argument("--jobs-json", required=True)
    parser.add_argument("--planned-gating", required=True)
    parser.add_argument("--subject-repository", required=True)
    parser.add_argument("--subject-sha", required=True)
    parser.add_argument("--subject-visibility", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    if len(args.subject_sha) != 40:
        print("::error::subject-sha must be a full 40-character SHA", file=sys.stderr)
        return 1

    with open(args.run_json, encoding="utf-8") as f:
        run = json.load(f)
    with open(args.jobs_json, encoding="utf-8") as f:
        jobs_doc = json.load(f)
    jobs = jobs_doc.get("jobs", jobs_doc if isinstance(jobs_doc, list) else [])

    record, ok = build_base_record(
        run,
        jobs,
        planned_gating=[g for g in args.planned_gating.split(",") if g],
        subject_repository=args.subject_repository,
        subject_sha=args.subject_sha,
        subject_visibility=args.subject_visibility,
    )
    payload = canonical_bytes(record)
    with open(args.output, "wb") as f:
        f.write(payload)
    with open(args.output + ".sha256", "w", encoding="utf-8") as f:
        f.write(hashlib.sha256(payload).hexdigest() + "\n")
    print(f"effective-runtime-receipt-base-digest={hashlib.sha256(payload).hexdigest()}")
    print("effective-runtime-receipt-stage=preterminal")
    if not ok:
        print(
            "::error::referenced_workflows is empty/unavailable — the reusable-workflow chain is UNMEASURED and this aggregate must fail (P20).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
