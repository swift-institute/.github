#!/usr/bin/env python3
"""validate-cache-policy.py — verify [CI-040] no `.build/` cache and
[CI-042] no `restore-keys` partial-prefix matching.

Pilot 14 (CI-040) + pilot 16 (CI-042) of `/promote-rule` (2026-05-14) —
companion to validate-cache-policy.yml. Migrated to use validate_lib
shared helpers (emit + require_yaml) in Phase B-1 of
CI-REVIEW-PHASE-B-DESIGN-2026-05-14 §4 step 6 as the canary
demonstrating the boilerplate-collapse pattern.

Single-repo multi-file integrity check sub-shape (same shape as
validate-visibility-gate.py from pilot 13).

Rules checked:
  [CI-040]  CI workflows MUST NOT cache `.build/` directories via
            `actions/cache@vN` or equivalent mechanism. Detection: any
            `actions/cache@*` step whose `with.path:` references a `.build`
            path component.

            NO CARVE-OUT. The L1-embedded-job exemption that stood here
            until 2026-07-31 is retired (swift-institute/.github#161): the
            `embedded` job in swift-primitives/.github's swift-ci.yml was
            restoring ~84MB of `.build` and reporting "Build complete!" with
            zero `Compiling` lines, so the leg's green attested a cache
            restore rather than a compile. An exact-match key does not save
            it — the key hashed only the manifests, so it encoded neither the
            toolchain (a 6.3-built `.build` satisfied a 6.5-dev nightly job)
            nor branch-pinned dependency contents. Under gitignored
            `Package.resolved` plus branch pins, no key can prove a `.build`
            represents the resolved graph, which is why the rule is now what
            the ci-cd skill already said it was: absolute.

            Tool-binary caches (SwiftLint, lychee, yq, gh CLI) are
            permitted per [CI-044] and are out of scope for [CI-040] —
            their `with.path:` does NOT reference `.build/`.

  [CI-042]  Even in cache configurations outside the `.build/` cache (per
            [CI-044] tool-binary carve-out), `restore-keys:` MUST NOT be
            used. Cache hits MUST be exact-match-only. Detection: any
            `actions/cache@*` step whose `with:` block contains a
            `restore-keys` key (regardless of path).

            No carve-out — the rule applies to all cache classes.
            Tool-binary caches (CI-044) and any other permitted cache use
            MUST be exact-match-only.

Both rules iterate the same per-step inspection; the validator may emit
both findings on a single step (e.g., a `.build`-path cache with
`restore-keys`).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

# Match `.build` as a path component: at start, after `/`, or as the
# whole path. Examples that match: `.build`, `.build/`, `./.build`,
# `/path/.build`. Excludes: `mybuild`, `.build-extra` (different suffix).
BUILD_PATH_RE = re.compile(r"(^|/)\.build(/|$)")


def cache_targets_build(with_block: dict) -> bool:
    """Check if a cache step's `with.path` references `.build/`.

    `path:` may be a single string or a multi-line scalar (YAML `|` block);
    both resolve to a Python string after safe_load.
    """
    path = with_block.get("path", "")
    if not isinstance(path, str):
        return False
    # Check every line independently — the path may be multi-line.
    for line in path.splitlines():
        if BUILD_PATH_RE.search(line):
            return True
    return False


def check_workflow(repo: str, wf_path: Path) -> int:
    """Check every job's steps for forbidden `.build/` cache usage ([CI-040])
    and forbidden `restore-keys` partial-prefix matching ([CI-042]).

    Returns count of findings (sum across both rules).
    """
    try:
        data = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit(repo, "CI-040", f"{wf_path.name}: YAML parse failed: {e}")
        return 1
    if not isinstance(data, dict):
        return 0
    jobs = data.get("jobs")
    if not isinstance(jobs, dict):
        return 0
    findings = 0
    for job_name, job_data in jobs.items():
        if not isinstance(job_data, dict):
            continue
        steps = job_data.get("steps", [])
        if not isinstance(steps, list):
            continue
        for step in steps:
            if not isinstance(step, dict):
                continue
            uses = str(step.get("uses", ""))
            if not uses.startswith("actions/cache"):
                continue
            with_block = step.get("with")
            if not isinstance(with_block, dict):
                continue
            # [CI-040] check: any cache step targeting .build. No carve-out.
            if cache_targets_build(with_block):
                path_val = with_block.get("path", "")
                emit(
                    repo,
                    "CI-040",
                    f"{wf_path.name}: job {job_name!r} caches `.build/` via "
                    f"`actions/cache` per [CI-040] — the no-`.build/`-cache "
                    f"rule is permanent AND carve-out-free under the "
                    f"gitignored-Package.resolved + branch-pinned-deps "
                    f"constraint set. No key, however exact, can prove a "
                    f"restored `.build` matches the resolved graph or the "
                    f"running toolchain; a hit turns the job's green into "
                    f"evidence of a restore rather than a compile "
                    f"(swift-institute/.github#161). path={path_val!r}",
                )
                findings += 1
            # [CI-042] check: any cache step with `restore-keys` is a violation.
            # No carve-out — exact-match-only applies to all cache classes
            # (build cache, tool-binary cache, anything else).
            if "restore-keys" in with_block:
                rk_val = with_block.get("restore-keys", "")
                rk_preview = str(rk_val).replace("\n", " ").strip()[:80]
                emit(
                    repo,
                    "CI-042",
                    f"{wf_path.name}: job {job_name!r} cache step uses "
                    f"`restore-keys:` per [CI-042] — partial-prefix fallback "
                    f"silently serves stale state. Cache hits MUST be "
                    f"exact-match-only (remove `restore-keys:`). "
                    f"restore-keys preview: {rk_preview!r}",
                )
                findings += 1
    return findings


def main(repo: str, repo_root: str) -> int:
    """Validate every workflow under <repo_root>/.github/workflows/ for the
    no-`.build/`-cache rule."""
    findings = 0
    workflows_dir = Path(repo_root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return 0
    targets = sorted(list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml")))
    for wf in targets:
        findings += check_workflow(repo, wf)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-cache-policy.py <owner/name> <repo_root>  # checks CI-040 + CI-042")
    main(sys.argv[1], sys.argv[2])
