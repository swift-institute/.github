#!/usr/bin/env python3
"""
Build the machine-readable CI verdict inventory (Task 1-01,
swift-institute/.github#276, swift-institute/.github#281).

Parses the universal reusable workflow (`.github/workflows/swift-ci.yml`)
and the three layer wrappers (`swift-primitives/.github`,
`swift-standards/.github`, `swift-foundations/.github`, each at
`.github/workflows/swift-ci.yml`) and emits ONE JSON document enumerating,
for the CURRENT shipped bytes:

  - every job, its runner pool, its `needs`/`if` shape, and its DAG wave;
  - the Plan leg-token vocabulary and which jobs each tier selects;
  - the gating (required) vs advisory job partition, cross-checked against
    `ci-ok`'s / `advisory-summary`'s own `needs:` lists;
  - the outer/inner aggregate relationship: each layer wrapper's own
    `ci-ok` (outer) trusts the universal workflow's `ci-ok` (inner, reached
    via the wrapper's `matrix` job) as a single opaque success/not-success
    signal, and does not re-derive it; a GitHub-native matrix job
    (`apple-simulator-build`) is the only other inner aggregate, and it
    feeds nothing gating;
  - private-visibility guard coverage (which jobs carry
    `!github.event.repository.private` and therefore report no signal at
    all on a private repository run);
  - the nested `Tests/Package.swift` execution sites;
  - the token/permissions boundary (every job's `permissions:` block);
  - the cache policy (which paths are cached; confirms `.build/` never is);
  - the required-check context string, cross-checked against
    `Tools/repository-policy`'s source-controlled ruleset policy;
  - each layer wrapper's layer-required jobs that sit OUTSIDE the universal
    verdict, and whether the wrapper's own `ci-ok` gates on them.

This is deliberately a STRUCTURAL inventory extracted from the shipped
YAML, not a hand-maintained description: `.github/scripts/tests/
test-verdict-inventory.py` regenerates it from the same checkout and
diffs byte-for-byte, so drift between this file and the workflows it
describes is a test failure, not a silent staleness.

Usage:
  python3 .github/scripts/build-verdict-inventory.py \
      --universal .github/workflows/swift-ci.yml \
      --wrapper primitives=<path> --wrapper standards=<path> --wrapper foundations=<path> \
      > .github/scripts/tests/fixtures/verdict-inventory.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

SCHEMA_VERSION = 1

# GitHub Actions' own enum for `needs.<job_id>.result` / a job's own
# `job.status` conclusion. Source: GitHub Actions "Contexts" reference —
# the `needs` context result is exactly one of these four strings.
POSSIBLE_JOB_CONCLUSIONS = ["success", "failure", "cancelled", "skipped"]

# Build-tier leg tokens are computed at runtime (one of macos-release /
# linux-release / windows-release is chosen as the platform-support-ordered
# primary); the full-tier token list is a static literal in the Plan job's
# "Classify tier" step and is reproduced here for the inventory's
# `plan.full_tier_legs` field. Kept in lockstep with that literal by
# `test-verdict-inventory.py::test_full_tier_legs_literal_matches_source`,
# which re-extracts the literal from the shipped step body rather than
# trusting this copy.
_FULL_TIER_LEGS_PATTERN = re.compile(r'''full\)\s+LEGS="([^"]+)"''')

# The "Resolve CI subject" / "Classify tier" / "Aggregate required-job
# results" step names, shared with test-ci-ok-aggregate.py's extractor.
RESOLVE_SUBJECT_STEP = "Resolve CI subject"
CLASSIFY_STEP = "Classify tier"
AGGREGATE_STEP = "Aggregate required-job results"
NESTED_TEST_MARKER = "Tests/Package.swift"


def _load(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _step_by_name(job: dict, name: str) -> dict | None:
    for step in job.get("steps", []) or []:
        if step.get("name") == name:
            return step
    return None


def _job_permissions(job: dict) -> dict:
    return job.get("permissions", {}) or {}


def _job_wave(jobs: dict, job_id: str, cache: dict[str, int]) -> int:
    """DAG wave: 0 for a job with no `needs`, else 1 + max(needs' waves).

    This is exactly the "sequential aggregate wave" structure — jobs at
    wave N cannot start acquiring a runner until every job they `needs`
    at wave < N has completed, so `ci-ok`/`advisory-summary` (which need
    the leg producers) always sit at a strictly higher wave than every
    leg they aggregate.
    """
    if job_id in cache:
        return cache[job_id]
    needs = jobs[job_id].get("needs") or []
    if isinstance(needs, str):
        needs = [needs]
    if not needs:
        cache[job_id] = 0
        return 0
    wave = 1 + max(_job_wave(jobs, n, cache) for n in needs if n in jobs)
    cache[job_id] = wave
    return wave


def build_universal_inventory(path: Path) -> dict:
    doc = _load(path)
    jobs = doc["jobs"]
    wave_cache: dict[str, int] = {}

    plan = jobs["plan"]
    classify = _step_by_name(plan, CLASSIFY_STEP)
    classify_body = classify.get("run", "") if classify else ""
    m = _FULL_TIER_LEGS_PATTERN.search(classify_body)
    full_tier_legs = m.group(1).split(",") if m else []

    ci_ok = jobs["ci-ok"]
    gating_jobs = [j for j in (ci_ok.get("needs") or []) if j != "plan"]

    advisory_summary = jobs.get("advisory-summary", {})
    advisory_jobs = [
        j for j in (advisory_summary.get("needs") or []) if j != "plan"
    ]

    job_entries = {}
    for job_id, job in jobs.items():
        entry = {
            "runner": job.get("runs-on") or job.get("uses") or None,
            "needs": (
                [job["needs"]] if isinstance(job.get("needs"), str)
                else list(job.get("needs") or [])
            ),
            "if": job.get("if"),
            "continue_on_error": bool(job.get("continue-on-error", False)),
            "permissions": _job_permissions(job),
            "private_guarded": "github.event.repository.private" in (job.get("if") or ""),
            "has_matrix": bool((job.get("strategy") or {}).get("matrix")),
            "matrix_axes": {
                k: v for k, v in ((job.get("strategy") or {}).get("matrix") or {}).items()
            },
            "posture": (
                "gating" if job_id in gating_jobs
                else "advisory" if job_id in advisory_jobs
                else "aggregate" if job_id in ("ci-ok", "advisory-summary")
                else "plan" if job_id == "plan"
                else "event-gated"
            ),
            "nested_test_detection": any(
                NESTED_TEST_MARKER in (step.get("run") or "")
                for step in job.get("steps", []) or []
            ),
            "step_names": [s.get("name") for s in job.get("steps", []) or []],
        }
        entry["wave"] = _job_wave(jobs, job_id, wave_cache)
        job_entries[job_id] = entry

    # Cache policy: enumerate every actions/cache step and its `path`; assert
    # none targets `.build`. (The assertion lives in the test suite; this is
    # the raw enumeration it asserts over.)
    cache_steps = []
    for job_id, job in jobs.items():
        for step in job.get("steps", []) or []:
            uses = step.get("uses", "") or ""
            if uses.startswith("actions/cache@"):
                cache_steps.append({
                    "job": job_id,
                    "step": step.get("name"),
                    "path": (step.get("with") or {}).get("path"),
                    "key": (step.get("with") or {}).get("key"),
                })

    return {
        "source_sha256": _sha256(path),
        "jobs": job_entries,
        "job_count": len(jobs),
        "gating_jobs": gating_jobs,
        "advisory_jobs": advisory_jobs,
        "plan": {
            "full_tier_legs": full_tier_legs,
            "resolve_subject_step": RESOLVE_SUBJECT_STEP,
            "classify_step": CLASSIFY_STEP,
        },
        "aggregate": {
            "ci_ok_needs": ci_ok.get("needs"),
            "ci_ok_step": AGGREGATE_STEP,
            "advisory_summary_needs": advisory_summary.get("needs"),
            "inner_matrix_jobs": [
                j for j, e in job_entries.items() if e["has_matrix"]
            ],
        },
        "cache_steps": cache_steps,
        "possible_job_conclusions": POSSIBLE_JOB_CONCLUSIONS,
        # Terminal contract (TX5, swift-institute/.github#276): caller job
        # `ci` -> wrapper `matrix` -> this workflow's own `ci-ok`.
        "required_check_context": "ci / matrix / ci-ok",
    }


def build_wrapper_inventory(layer: str, path: Path) -> dict:
    doc = _load(path)
    jobs = doc["jobs"]
    ci_ok = jobs.get("ci-ok", {})
    ci_ok_needs = list(ci_ok.get("needs") or [])
    layer_required_outside_universal = [
        job_id for job_id, job in jobs.items()
        if job_id not in ("matrix", "ci-ok")
    ]
    return {
        "layer": layer,
        "source_sha256": _sha256(path),
        "job_count": len(jobs),
        "jobs": {
            job_id: {
                "runner": job.get("runs-on") or job.get("uses") or None,
                "continue_on_error": bool(job.get("continue-on-error", False)),
                "in_ci_ok_needs": job_id in ci_ok_needs,
            }
            for job_id, job in jobs.items()
        },
        "ci_ok_needs": ci_ok_needs,
        "layer_required_jobs_outside_universal_verdict": [
            j for j in layer_required_outside_universal if j not in ci_ok_needs
        ],
    }


def build_inventory(universal_path: Path, wrapper_paths: dict[str, Path]) -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_by": "build-verdict-inventory.py",
        "universal": build_universal_inventory(universal_path),
        "wrappers": {
            layer: build_wrapper_inventory(layer, p)
            for layer, p in sorted(wrapper_paths.items())
        },
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--universal", required=True, type=Path)
    parser.add_argument(
        "--wrapper", action="append", default=[],
        help="layer=path, repeatable (e.g. primitives=/path/to/swift-ci.yml)",
    )
    args = parser.parse_args(argv)

    wrapper_paths = {}
    for item in args.wrapper:
        layer, _, path = item.partition("=")
        if not layer or not path:
            parser.error(f"--wrapper expects layer=path, got {item!r}")
        wrapper_paths[layer] = Path(path)

    inventory = build_inventory(args.universal, wrapper_paths)
    json.dump(inventory, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
