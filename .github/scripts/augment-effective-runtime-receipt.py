#!/usr/bin/env python3
"""augment-effective-runtime-receipt.py — post-completion collector for the
version-1 effective runtime receipt (TX7 receipt contract,
swift-institute/.github#276 §8.9; predicate P19).

Never invoked from the aggregate. After the producing run reaches
`status=completed`, this collector:

  1. downloads the base artifact and verifies the base record's digest;
  2. reads the completed run object and its complete paginated jobs
     collection through the GitHub API (`gh api`);
  3. requires immutable-identity equality between base and terminal reads
     (run id/attempt/head SHA/repository/workflow path);
  4. replaces ONLY the terminal facts (run conclusion, per-job
     conclusions), binds `baseReceiptDigest`, sets `attestationStage:
     "terminal"`, and computes the verdict: `MET` only when the run
     concluded success and no mandatory selected job is non-success
     (skipped/cancelled mandatory jobs cannot produce terminal MET).

Exits nonzero on: a not-completed run, wrong attempt, base/artifact digest
mismatch, immutable-identity mismatch, a non-null preterminal claim,
missing terminal conclusion, or unsafe data. No token, authorization
header, private coordinate, or machine path is serialized.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import zipfile

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "effective_runtime_receipt", os.path.join(_here, "effective-runtime-receipt.py")
)
base_mod = importlib.util.module_from_spec(_spec)
sys.modules["effective_runtime_receipt"] = base_mod
_spec.loader.exec_module(base_mod)


def gh_json(path: str):
    proc = subprocess.run(
        ["gh", "api", path], capture_output=True, text=True, timeout=180
    )
    if proc.returncode != 0:
        raise RuntimeError(f"gh api {path} failed: {proc.stderr.strip()[:300]}")
    return json.loads(proc.stdout)


def fetch_base(repo: str, run_id: int, artifact_name: str) -> tuple[dict, str]:
    artifacts = gh_json(f"repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100")
    match = [a for a in artifacts.get("artifacts", []) if a["name"] == artifact_name]
    if len(match) != 1:
        raise RuntimeError(
            f"expected exactly one artifact named {artifact_name}, found {len(match)}"
        )
    proc = subprocess.run(
        ["gh", "api", f"repos/{repo}/actions/artifacts/{match[0]['id']}/zip"],
        capture_output=True,
        timeout=300,
    )
    if proc.returncode != 0:
        raise RuntimeError("artifact download failed")
    with zipfile.ZipFile(io.BytesIO(proc.stdout)) as z:
        names = [n for n in z.namelist() if n.endswith(".base.json")]
        if len(names) != 1:
            raise RuntimeError(f"expected one .base.json in artifact, got {names}")
        payload = z.read(names[0])
        declared = None
        for n in z.namelist():
            if n.endswith(".sha256"):
                declared = z.read(n).decode().strip()
    actual = hashlib.sha256(payload).hexdigest()
    if declared is not None and declared != actual:
        raise RuntimeError("base artifact digest mismatch against its declared sha256")
    return json.loads(payload), actual


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--attempt", required=True, type=int)
    parser.add_argument("--base-artifact", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    try:
        base, base_digest = fetch_base(args.repo, args.run_id, args.base_artifact)
    except RuntimeError as e:
        print(f"::error::{e}", file=sys.stderr)
        return 1

    if base.get("attestationStage") != "preterminal" or base.get("baseReceiptDigest") is not None:
        print("::error::base record does not carry the preterminal null-digest shape", file=sys.stderr)
        return 1

    run = gh_json(f"repos/{args.repo}/actions/runs/{args.run_id}")
    if run.get("status") != "completed":
        print("::error::run is not completed; terminal augmentation is premature", file=sys.stderr)
        return 1
    if run.get("run_attempt") != args.attempt:
        print("::error::run attempt does not match the requested attempt", file=sys.stderr)
        return 1

    identity_pairs = [
        (base["run"]["id"], run.get("id"), "run.id"),
        (base["run"]["attempt"], run.get("run_attempt"), "run.attempt"),
        (base["run"]["headSha"], run.get("head_sha"), "run.headSha"),
        (base["run"]["repository"], run.get("repository", {}).get("full_name"), "run.repository"),
        (base["run"]["workflowPath"], run.get("path"), "run.workflowPath"),
    ]
    for base_value, live_value, name in identity_pairs:
        if base_value != live_value:
            print(f"::error::immutable identity mismatch on {name}: base={base_value!r} live={live_value!r}", file=sys.stderr)
            return 1

    jobs = []
    page = 1
    while True:
        doc = gh_json(f"repos/{args.repo}/actions/runs/{args.run_id}/jobs?per_page=100&page={page}")
        jobs.extend(doc.get("jobs", []))
        if len(doc.get("jobs", [])) < 100:
            break
        page += 1
    conclusion_by_id = {j["id"]: j.get("conclusion") for j in jobs}

    terminal = json.loads(json.dumps(base))  # deep copy
    terminal["attestationStage"] = "terminal"
    terminal["baseReceiptDigest"] = base_digest
    terminal["run"]["conclusion"] = run.get("conclusion")
    mandatory_bad = []
    for row in terminal["jobs"]:
        live = conclusion_by_id.get(row["id"], row["conclusion"])
        row["conclusion"] = live
        if row["mandatory"] and live != "success":
            mandatory_bad.append((row["name"], live))
    terminal["unmeasured"] = [
        u
        for u in terminal["unmeasured"]
        if u["field"] != "run.conclusion" and not u["field"].endswith(".conclusion")
    ]
    if run.get("conclusion") is None:
        print("::error::completed run exposes no conclusion", file=sys.stderr)
        return 1

    if terminal["verdict"] == "UNMEASURED" or not terminal["referencedWorkflows"]:
        terminal["verdict"] = "UNMEASURED"
    elif run.get("conclusion") == "success" and not mandatory_bad:
        terminal["verdict"] = "MET"
    else:
        terminal["verdict"] = "FAILED"
        for name, live in mandatory_bad:
            print(f"::warning::mandatory selected job {name!r} concluded {live!r}", file=sys.stderr)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    payload = base_mod.canonical_bytes(terminal)
    with open(args.output, "wb") as f:
        f.write(payload)
    print(f"terminal-receipt-digest={hashlib.sha256(payload).hexdigest()}")
    print(f"terminal-verdict={terminal['verdict']}")
    return 0 if terminal["verdict"] == "MET" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
