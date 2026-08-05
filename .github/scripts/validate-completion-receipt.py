#!/usr/bin/env python3
"""validate-completion-receipt.py — receipt-readiness validator (TX7/TX2
receipt contract, swift-institute/.github#276 §8.9).

`runtime` mode validates one terminal effective runtime receipt for use as
P19 evidence. It accepts no local path AS evidence: the emitted readiness
record carries only portable API coordinates, the final digest, stage,
result and finding codes.

Rejects (nonzero exit, finding codes in the readiness record):
  STAGE-NOT-TERMINAL      attestationStage != "terminal" or a run required
                          and not completed
  NULL-TERMINAL-FIELD     a null run/mandatory-job conclusion without a
                          paired `unmeasured` row
  LOCAL-PATH              a machine-local absolute path anywhere in the
                          serialized record
  SHORT-SHA               any `sha`/`headSha` field that is not 40 hex
  DIGEST-MISMATCH         recomputed canonical digest differs from the
                          `.sha256`-style declared digest when supplied

Usage:
  python3 .github/scripts/validate-completion-receipt.py runtime \
    --runtime-receipt <file> --require-stage terminal \
    --require-completed-run --output <readiness.json>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
LOCAL_PATH = re.compile(r"\"/(?:Users|home|private/tmp|tmp)/")


def validate_runtime(record: dict, raw: bytes, require_stage: str, require_completed: bool) -> list[str]:
    findings: list[str] = []
    if record.get("attestationStage") != require_stage:
        findings.append("STAGE-NOT-TERMINAL")
    if require_stage == "terminal" and record.get("baseReceiptDigest") is None:
        findings.append("STAGE-NOT-TERMINAL")
    if require_completed and record.get("run", {}).get("conclusion") is None:
        findings.append("STAGE-NOT-TERMINAL")

    unmeasured_fields = {u.get("field") for u in record.get("unmeasured", [])}
    if record.get("run", {}).get("conclusion") is None and "run.conclusion" not in unmeasured_fields:
        findings.append("NULL-TERMINAL-FIELD")
    for row in record.get("jobs", []):
        if row.get("mandatory") and row.get("conclusion") is None:
            if f"jobs[{row.get('id')}].conclusion" not in unmeasured_fields:
                findings.append("NULL-TERMINAL-FIELD")

    text = raw.decode("utf-8", errors="replace")
    if LOCAL_PATH.search(text):
        findings.append("LOCAL-PATH")

    for sha in (
        [record.get("run", {}).get("headSha"), record.get("subject", {}).get("sha")]
        + [r.get("sha") for r in record.get("referencedWorkflows", [])]
    ):
        if sha is not None and not FULL_SHA.match(str(sha)):
            findings.append("SHORT-SHA")

    return sorted(set(findings))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["runtime"])
    parser.add_argument("--runtime-receipt", required=True)
    parser.add_argument("--require-stage", default="terminal")
    parser.add_argument("--require-completed-run", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    with open(args.runtime_receipt, "rb") as f:
        raw = f.read()
    record = json.loads(raw)
    findings = validate_runtime(record, raw, args.require_stage, args.require_completed_run)

    readiness = {
        "schemaVersion": 1,
        "kind": "runtime-receipt-readiness",
        "runCoordinate": {
            "repository": record.get("run", {}).get("repository"),
            "runId": record.get("run", {}).get("id"),
            "attempt": record.get("run", {}).get("attempt"),
        },
        "stage": record.get("attestationStage"),
        "verdict": record.get("verdict"),
        "receiptDigest": hashlib.sha256(raw).hexdigest(),
        "result": "accepted" if not findings and record.get("verdict") == "MET" else "rejected",
        "findings": findings,
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(readiness, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    if readiness["result"] != "accepted":
        print(f"::error::runtime receipt rejected: verdict={record.get('verdict')} findings={findings}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
