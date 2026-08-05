#!/usr/bin/env python3
"""validate-completion-receipt.py — the §13.3 machine readiness gate
(swift-institute/.github#276; completion programme §13.3, §6.3 as amended by
Corrigendum §11.2).

Two strict modes:

  runtime     validates one terminal augmented runtime receipt for use as
              P19 evidence.
  completion  validates the assembled §6.3 source data (`receipt-inputs.json`)
              plus the runtime readiness records; `--phase pre-finalization`
              gates R1 step 1, `--phase post-finalization` gates R1 step 8.

Fixed-schema JSON output for both modes:
  {"schemaVersion":1,"mode":"runtime|completion","result":"PASS|FAIL",
   "findings":[{"code","subject","detail"}],
   "evidence":[{"runId","runAttempt","headSha","terminalReceiptDigest"}]}

Exit semantics: 0 success; 1 invalid/incomplete record; 2 unavailable
required evidence. `evidence` never carries a filesystem path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
LOCAL_PATH = re.compile(r"\"/(?:Users|home|private/tmp|tmp|var/folders)/")
SHA_KEY = re.compile(r"(sha|Sha|SHA)($|256$|[A-Z_].*)?")

AUTHORITY_SHA256 = {
    "refactorProgramme": "184db8ef230cd7e532f9aeb167a51508bc897f8221ec935cb5a776ca1eaf62ef",
    "completionProgramme": "62e315c42f6ec6b34320af560697fc8bfb772ab655ddc4c65456ff04cd90d21f",
}

REQUIRED_TABLE_COUNT = 16
REQUIRED_ASSERTION_COUNT = 16


def finding(code: str, subject: str, detail: str) -> dict:
    return {"code": code, "subject": subject, "detail": detail}


def scan_serialized(raw_text: str, subject: str, findings: list[dict]) -> None:
    if LOCAL_PATH.search(raw_text):
        findings.append(finding("LOCAL-PATH", subject, "machine-local absolute path present"))


def scan_shas(obj, path: str, findings: list[dict]) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else k
            if isinstance(v, str) and SHA_KEY.search(k) and v not in ("", "unmeasured"):
                if not (FULL_SHA.match(v) or HEX64.match(v)):
                    findings.append(finding("SHORT-SHA", p, f"non-conforming SHA value {v[:12]!r}"))
            else:
                scan_shas(v, p, findings)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            scan_shas(v, f"{path}[{i}]", findings)


def validate_runtime(record: dict, raw: bytes, require_stage: str, require_completed: bool) -> list[dict]:
    findings: list[dict] = []
    if record.get("attestationStage") != require_stage:
        findings.append(finding("STAGE-NOT-TERMINAL", "attestationStage",
                                f"stage {record.get('attestationStage')!r} != required {require_stage!r}"))
    if require_stage == "terminal" and record.get("baseReceiptDigest") is None:
        findings.append(finding("STAGE-NOT-TERMINAL", "baseReceiptDigest", "terminal record lacks base digest"))
    run = record.get("run", {}) or {}
    if require_completed and run.get("conclusion") is None:
        findings.append(finding("NULL-TERMINAL-FIELD", "run.conclusion", "null conclusion on required-completed run"))

    unmeasured_fields = {u.get("field") for u in record.get("unmeasured", []) or []}
    if run.get("conclusion") is None and "run.conclusion" not in unmeasured_fields:
        findings.append(finding("NULL-TERMINAL-FIELD", "run.conclusion", "null without paired unmeasured row"))

    jobs = record.get("jobs", []) or []
    for row in jobs:
        jid = row.get("id")
        if row.get("mandatory"):
            c = row.get("conclusion")
            if c is None and f"jobs[{jid}].conclusion" not in unmeasured_fields:
                findings.append(finding("NULL-TERMINAL-FIELD", f"jobs[{jid}]", "null mandatory conclusion"))
            if c in ("skipped", "cancelled"):
                findings.append(finding("MANDATORY-JOB-NOT-SUCCESS", f"jobs[{jid}]", f"mandatory job {c}"))

    total = record.get("jobsTotalCount")
    if total is not None and total != len(jobs):
        findings.append(finding("JOBS-PAGINATION-INCOMPLETE", "jobs",
                                f"jobsTotalCount={total} but {len(jobs)} rows present"))

    scan_serialized(raw.decode("utf-8", errors="replace"), "runtime-receipt", findings)
    scan_shas(record, "", findings)
    return findings


def load_readiness(directory: str, findings: list[dict]) -> dict[tuple, dict]:
    records: dict[tuple, dict] = {}
    if not os.path.isdir(directory):
        findings.append(finding("READINESS-UNAVAILABLE", "runtime-readiness-dir", "directory unreadable"))
        return records
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json") or name.startswith("completion-"):
            continue
        try:
            with open(os.path.join(directory, name), "rb") as f:
                rec = json.load(f)
        except (OSError, ValueError):
            findings.append(finding("READINESS-UNAVAILABLE", name, "unreadable readiness record"))
            continue
        for ev in rec.get("evidence", []) or []:
            key = (ev.get("runId"), ev.get("runAttempt"))
            records[key] = {"record": rec, "evidence": ev}
    return records


def validate_completion(inputs: dict, raw: bytes, phase: str, readiness_dir: str,
                        link_readback: dict | None) -> tuple[list[dict], list[dict], bool]:
    findings: list[dict] = []
    evidence: list[dict] = []
    unavailable = False

    authority = inputs.get("authority", {}) or {}
    for key, expected in AUTHORITY_SHA256.items():
        if authority.get(key) != expected:
            findings.append(finding("AUTHORITY-NOT-VERIFIED", key, "digest absent or differs from governing value"))

    predicates = inputs.get("predicates", {}) or {}
    for i in range(1, 27):
        p = predicates.get(f"P{i}")
        state = (p or {}).get("state", "")
        ok = state == "MET" or state.startswith("MET (") or (i == 21 and state == "DESCOPED")
        if state.startswith("MET (") and not (p or {}).get("ruling"):
            ok = False
        if not ok:
            findings.append(finding("PREDICATE-NOT-TERMINAL", f"P{i}", f"state {state!r}"))
    for i in (27, 28):
        p = predicates.get(f"P{i}") or {}
        if phase == "pre-finalization":
            if not p.get("nonPerformativeLimbsSupportable"):
                findings.append(finding("PREDICATE-NOT-TERMINAL", f"P{i}", "non-performative limbs unsupported"))
        else:
            if p.get("state") != "MET":
                findings.append(finding("PREDICATE-NOT-TERMINAL", f"P{i}", f"state {p.get('state')!r}"))

    tables = inputs.get("tables", []) or []
    populated = [t for t in tables if t.get("populated")]
    if len(populated) != REQUIRED_TABLE_COUNT:
        findings.append(finding("RECEIPT-STRUCTURE-INCOMPLETE", "tables",
                                f"{len(populated)}/{REQUIRED_TABLE_COUNT} tables populated"))
    if not any(t.get("nameReservationField") for t in tables):
        findings.append(finding("RECEIPT-STRUCTURE-INCOMPLETE", "tables[8]",
                                "Corrigendum §11.2 name-reservation field absent"))
    if not inputs.get("workspaceReconciliation"):
        findings.append(finding("RECEIPT-STRUCTURE-INCOMPLETE", "workspaceReconciliation", "list empty"))
    assertions = inputs.get("assertions", []) or []
    supportable = [a for a in assertions if a.get("supportable")]
    if len(supportable) != REQUIRED_ASSERTION_COUNT:
        findings.append(finding("RECEIPT-STRUCTURE-INCOMPLETE", "assertions",
                                f"{len(supportable)}/{REQUIRED_ASSERTION_COUNT} assertions supportable"))

    if not inputs.get("positiveControls"):
        findings.append(finding("MISSING-POSITIVE-CONTROL", "positiveControls", "no recorded positive control"))
    for surface in ("compatibilityRemoved", "holdsRemoved", "destructiveOperationsAccounted",
                    "fleetDispositionImplemented", "fleetDispositionAuthorized",
                    "privateCoordinatesOpaque"):
        if not inputs.get(surface):
            findings.append(finding("PROPOSITION-FALSE", surface, "required proposition not true"))

    amendment = inputs.get("performativeAmendment", {}) or {}
    if not (amendment.get("located") and amendment.get("ruling")):
        findings.append(finding("PROPOSITION-FALSE", "performativeAmendment", "amendment not located/exact"))

    review = inputs.get("externalReview", {}) or {}
    if not str(review.get("verdict", "")).startswith("ACCEPTED FOR R1"):
        findings.append(finding("EXTERNAL-REVIEW-NOT-ACCEPTED", "externalReview",
                                f"verdict {review.get('verdict')!r}"))

    cand = inputs.get("receiptCandidateDigest")
    if phase == "pre-finalization" and not (isinstance(cand, str) and HEX64.match(cand)):
        findings.append(finding("CANDIDATE-DIGEST-MISSING", "receiptCandidateDigest", "absent or not 64-hex"))

    readiness = load_readiness(readiness_dir, findings)
    if any(f["code"] == "READINESS-UNAVAILABLE" for f in findings):
        unavailable = True
    for row in inputs.get("runtimeReceipts", []) or []:
        key = (row.get("runId"), row.get("runAttempt"))
        match = readiness.get(key)
        subject = f"runtimeReceipts[{row.get('runId')}/{row.get('runAttempt')}]"
        if match is None:
            findings.append(finding("READINESS-UNAVAILABLE", subject, "no readiness record for cited receipt"))
            unavailable = True
            continue
        rec, ev = match["record"], match["evidence"]
        if rec.get("result") != "PASS":
            findings.append(finding("RUNTIME-RECEIPT-REJECTED", subject, "cited readiness record is FAIL"))
        if ev.get("headSha") != row.get("headSha") or ev.get("terminalReceiptDigest") != row.get("digest"):
            findings.append(finding("RECEIPT-BINDING-MISMATCH", subject,
                                    "run/attempt/head/digest binding differs from readiness record"))
        evidence.append({"runId": row.get("runId"), "runAttempt": row.get("runAttempt"),
                         "headSha": row.get("headSha"), "terminalReceiptDigest": row.get("digest")})

    if phase == "post-finalization":
        lr = link_readback or {}
        if not lr:
            findings.append(finding("READINESS-UNAVAILABLE", "link-readback", "post-finalization readback absent"))
            unavailable = True
        else:
            if lr.get("goalState") != "closed" or lr.get("goalStateReason") != "completed":
                findings.append(finding("PROPOSITION-FALSE", "goal", "Goal not closed completed at readback"))
            rc = lr.get("receiptCommit", "")
            if not FULL_SHA.match(str(rc)):
                findings.append(finding("SHORT-SHA", "receiptCommit", "receipt commit not full SHA"))
            if not (isinstance(lr.get("receiptSha256"), str) and HEX64.match(lr["receiptSha256"])):
                findings.append(finding("PROPOSITION-FALSE", "receiptSha256", "receipt byte digest absent"))
            if not lr.get("linkCommentId"):
                findings.append(finding("PROPOSITION-FALSE", "linkCommentId", "follow-up link comment absent"))

    scan_serialized(raw.decode("utf-8", errors="replace"), "receipt-inputs", findings)
    scan_shas(inputs, "", findings)
    return findings, evidence, unavailable


def emit(mode: str, findings: list[dict], evidence: list[dict], output: str) -> dict:
    result = {
        "schemaVersion": 1,
        "mode": mode,
        "result": "PASS" if not findings else "FAIL",
        "findings": findings,
        "evidence": evidence,
    }
    with open(output, "w", encoding="utf-8") as f:
        json.dump(result, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["runtime", "completion"])
    parser.add_argument("--runtime-receipt")
    parser.add_argument("--require-stage", default="terminal")
    parser.add_argument("--require-completed-run", action="store_true")
    parser.add_argument("--phase", choices=["pre-finalization", "post-finalization"])
    parser.add_argument("--receipt-input")
    parser.add_argument("--runtime-readiness-dir")
    parser.add_argument("--link-readback")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    if args.mode == "runtime":
        if not args.runtime_receipt:
            parser.error("runtime mode requires --runtime-receipt")
        try:
            with open(args.runtime_receipt, "rb") as f:
                raw = f.read()
            record = json.loads(raw)
        except (OSError, ValueError):
            emit("runtime", [finding("READINESS-UNAVAILABLE", "runtime-receipt", "unreadable")], [], args.output)
            return 2
        findings = validate_runtime(record, raw, args.require_stage, args.require_completed_run)
        run = record.get("run", {}) or {}
        evidence = [{"runId": run.get("id"), "runAttempt": run.get("attempt"),
                     "headSha": run.get("headSha"),
                     "terminalReceiptDigest": hashlib.sha256(raw).hexdigest()}]
        if record.get("verdict") != "MET":
            findings.append(finding("RUNTIME-RECEIPT-REJECTED", "verdict",
                                    f"verdict {record.get('verdict')!r} is not MET"))
        result = emit("runtime", findings, evidence, args.output)
        return 0 if result["result"] == "PASS" else 1

    if not (args.phase and args.receipt_input and args.runtime_readiness_dir):
        parser.error("completion mode requires --phase, --receipt-input, --runtime-readiness-dir")
    try:
        with open(args.receipt_input, "rb") as f:
            raw = f.read()
        inputs = json.loads(raw)
    except (OSError, ValueError):
        emit("completion", [finding("READINESS-UNAVAILABLE", "receipt-input", "unreadable")], [], args.output)
        return 2
    link_readback = None
    if args.link_readback:
        try:
            with open(args.link_readback, "rb") as f:
                link_readback = json.load(f)
        except (OSError, ValueError):
            link_readback = None
    findings, evidence, unavailable = validate_completion(
        inputs, raw, args.phase, args.runtime_readiness_dir, link_readback)
    result = emit("completion", findings, evidence, args.output)
    if result["result"] == "PASS":
        return 0
    return 2 if unavailable else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
