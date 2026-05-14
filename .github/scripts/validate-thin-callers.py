#!/usr/bin/env python3
"""validate-thin-callers.py — verify per-package CI workflows are thin callers.

Pilot 7 of `/promote-rule` (2026-05-14) — companion to validate-thin-callers.yml.
Pilot 17 (2026-05-14) extended with [CI-030] @main-pin check + [CI-059]
`secrets: inherit` check (compose-in-script per the per-job `ci.yml` shared domain).

Rules checked:
  [GH-REPO-074]  Per-package `.github/workflows/ci.yml` MUST be a thin caller
                 to centralized reusable workflows:
                   - canonical `ci.yml` MUST NOT contain inline `runs-on:` in
                     any job
                   - canonical `ci.yml` MUST NOT contain inline `steps:` in
                     any job
                   - canonical `ci.yml` MUST have at least one job using
                     `uses:` to reference a centralized reusable workflow

                 Per-package `swift-format.yml` and `swiftlint.yml` MUST NOT
                 exist as standalone files (post-2026-05-10 consolidation —
                 format/lint legs are part of the layer wrapper's universal
                 matrix via swift-ci.yml).

                 Carve-out: any workflow file with `on: workflow_call:` trigger
                 is exempt from the inline-job checks. Tool-reusable workflows
                 ([GH-REPO-077] tool-host class) intentionally host action
                 refs and are not subject to thin-caller discipline.

  [CI-030]      Caller `uses:` references to intra-Institute reusable workflows
                MUST pin to `@main` during active dev. Tag pins (`@v1`,
                `@v1.0.0`) and SHA pins are forbidden until the reusable surface
                stabilizes at `@v1`.

                Intra-Institute discriminator: the `.github/.github/workflows/`
                double-infix path shape, unique to org-`.github`-repo reusable
                workflows. Third-party action refs (`actions/checkout@v6`) use
                a different shape and are exempt per [CI-107] latest-major-tag
                discipline.

  [CI-059]      Every per-repo `ci.yml` job that invokes an intra-Institute
                reusable workflow MUST carry `secrets: inherit` in the same
                job. Explicit per-secret forwarding (`secrets: { NAME: ... }`
                or `secrets:` block form) is forbidden once the underlying
                secret is org-level per [CI-060]. Omission is forbidden per
                shape-uniformity ([CI-031]) — even consumers whose dependency
                graph is fully public carry `secrets: inherit` as a single
                canonical shape.

Both CI-030 and CI-059 inherit the GH-REPO-074 file-level carve-out: workflows
that are themselves reusables (`on: workflow_call:`) are exempt — the rules
constrain *callers* to centralized reusables, not the reusables themselves.

Detection shape: line-anchored regex against the workflow YAML plus an
indentation-tracking per-job iterator for [CI-059] (which needs same-job
co-presence of `uses:` and `secrets: inherit`). All without a YAML parser
dependency. Mirrors the dependency-free shape of other validators in this
directory.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path
from typing import Iterator, Tuple

# Job-level keys live at column-2+ indentation under `jobs.<job>:`. The
# line-anchored `^\s+<key>:` form matches every YAML canonical indent
# (2-space, 4-space) without false-positive at column-0.
INLINE_RUNS_ON = re.compile(r"^\s+runs-on:", re.MULTILINE)
INLINE_STEPS = re.compile(r"^\s+steps:\s*$", re.MULTILINE)
JOB_USES = re.compile(r"^\s+uses:\s+\S+", re.MULTILINE)
WORKFLOW_CALL_TRIGGER = re.compile(r"^\s*workflow_call:", re.MULTILINE)

# Intra-Institute reusable workflow ref shape.
# Canonical path: `<org>/.github/.github/workflows/<file>@<ref>`.
# The `.github/.github/workflows/` double-infix is unique to org-`.github`-repo
# reusable workflows (the calling repo is third-party from GitHub's POV — the
# `<org>/.github` repo's `.github/workflows/` directory is reached via the
# nested `.github` repo path). Third-party reusable workflows use the single-
# infix `<owner>/<repo>/.github/workflows/<file>@<ref>` shape and are exempt
# from CI-030 + CI-059.
USES_INTRA_INSTITUTE = re.compile(
    r"^(\s+)uses:\s+([\w.-]+/\.github/\.github/workflows/[\w.-]+)@(\S+)",
    re.MULTILINE,
)

# `secrets: inherit` declaration in a job body. Permits trailing comment.
HAS_SECRETS_INHERIT = re.compile(
    r"^\s+secrets:\s+inherit\s*(#.*)?$",
    re.MULTILINE,
)

# `secrets:` block-form opener — explicit forwarding (followed by indented children).
# Distinguished from `secrets: inherit` by absence of the `inherit` literal.
HAS_SECRETS_BLOCK = re.compile(
    r"^\s+secrets:\s*(#.*)?$",
    re.MULTILINE,
)

# `secrets: { ... }` inline-map form — also explicit forwarding.
HAS_SECRETS_INLINE_MAP = re.compile(
    r"^\s+secrets:\s*\{",
    re.MULTILINE,
)

# Job-name line under `jobs:` — 2-space indent, identifier, colon, optional
# trailing comment. `\w` and `-` cover all valid job-name shapes in the
# ecosystem.
JOB_NAME_LINE = re.compile(r"^([\w-]+):\s*(#.*)?$")


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def is_workflow_call(text: str) -> bool:
    """True if the workflow's `on:` block declares the `workflow_call:` trigger.

    Per [GH-REPO-074]'s tool-reusables carve-out, workflows that ARE the
    reusable (declared with `workflow_call:`) are exempt from the inline-job
    checks because hosting action refs is intentional for tool-host packages
    per [GH-REPO-077].
    """
    return bool(WORKFLOW_CALL_TRIGGER.search(text))


def iter_jobs(text: str) -> Iterator[Tuple[str, str]]:
    """Yield (job_name, job_body) for each top-level job under `jobs:`.

    Indentation-tracking parser: locates `jobs:` at column 0, then treats
    every line at 2-space indent with `<name>:` shape as a job boundary.
    Lines at deeper indent (or blank/comment lines between jobs) attribute
    to the current job's body. Stops at the first column-0 non-blank line
    after the jobs block.

    Canonical YAML structure assumed (matches every consumer in the
    ecosystem post-uniformity sweep):

        jobs:
          <job-name>:
            <body-key>: <value>
            <body-key>: <value>
          <next-job>:
            ...
    """
    lines = text.split("\n")
    jobs_start = None
    for i, line in enumerate(lines):
        if re.match(r"^jobs:\s*(#.*)?$", line):
            jobs_start = i + 1
            break
    if jobs_start is None:
        return

    current_job: str | None = None
    current_body: list[str] = []

    for i in range(jobs_start, len(lines)):
        line = lines[i]
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break  # top-level key past jobs:; jobs block done
        stripped = line.lstrip()
        if not stripped:
            if current_job is not None:
                current_body.append(line)
            continue
        indent = len(line) - len(stripped)
        if indent == 2 and JOB_NAME_LINE.match(stripped):
            if current_job is not None:
                yield current_job, "\n".join(current_body)
            current_job = JOB_NAME_LINE.match(stripped).group(1)
            current_body = []
        else:
            if current_job is not None:
                current_body.append(line)

    if current_job is not None:
        yield current_job, "\n".join(current_body)


def check_ci_030(repo: str, text: str) -> int:
    """Check [CI-030]: intra-Institute reusable refs MUST pin to @main."""
    findings = 0
    for match in USES_INTRA_INSTITUTE.finditer(text):
        path = match.group(2)
        ref = match.group(3)
        if ref == "main":
            continue
        emit(
            repo,
            "CI-030",
            f".github/workflows/ci.yml `uses: {path}@{ref}` — per [CI-030] "
            f"intra-Institute reusable refs MUST pin to `@main` during active "
            f"dev. Tag pins (`@v1`, `@v1.0.0`) and SHA pins are forbidden "
            f"until the reusable surface stabilizes at `@v1` per "
            f"`swift-institute/Research/ci-centralization-strategy.md`.",
        )
        findings += 1
    return findings


def check_ci_059(repo: str, text: str) -> int:
    """Check [CI-059]: jobs invoking intra-Institute reusables MUST carry
    `secrets: inherit` in the same job."""
    findings = 0
    for job_name, job_body in iter_jobs(text):
        if not USES_INTRA_INSTITUTE.search(job_body):
            continue  # job doesn't invoke an intra-Institute reusable
        if HAS_SECRETS_INHERIT.search(job_body):
            continue  # CI-059 satisfied
        # Job invokes intra-Institute reusable AND lacks `secrets: inherit`.
        # Distinguish explicit-forwarding from omission for a clearer message.
        if HAS_SECRETS_BLOCK.search(job_body) or HAS_SECRETS_INLINE_MAP.search(job_body):
            emit(
                repo,
                "CI-059",
                f".github/workflows/ci.yml job `{job_name}` invokes an "
                f"intra-Institute reusable with explicit `secrets:` "
                f"forwarding — per [CI-059] this MUST use `secrets: inherit` "
                f"instead. Org-level secrets per [CI-060] obviate explicit "
                f"per-secret forwarding; explicit forwarding is dead "
                f"boilerplate that drifts at every new secret addition.",
            )
        else:
            emit(
                repo,
                "CI-059",
                f".github/workflows/ci.yml job `{job_name}` invokes an "
                f"intra-Institute reusable without `secrets: inherit` — per "
                f"[CI-059] every per-repo `uses:` invocation of an "
                f"intra-Institute reusable MUST include `secrets: inherit` "
                f"(single canonical shape per [CI-031], universal across "
                f"consumers regardless of dependency-graph visibility).",
            )
        findings += 1
    return findings


def check_ci_yml(repo: str, ci_path: Path) -> int:
    """Validate `<repo>/.github/workflows/ci.yml` against thin-caller rules."""
    try:
        text = ci_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    if is_workflow_call(text):
        return 0  # tool-reusable carve-out (file-level, applies to all rules)
    findings = 0
    if INLINE_RUNS_ON.search(text):
        emit(
            repo,
            "GH-REPO-074",
            ".github/workflows/ci.yml contains inline `runs-on:` — "
            "per [GH-REPO-074] this MUST be a thin caller delegating to a "
            "centralized reusable workflow via `uses:`. Reference shape: "
            "swift-carrier-primitives/.github/workflows/ci.yml.",
        )
        findings += 1
    if INLINE_STEPS.search(text):
        emit(
            repo,
            "GH-REPO-074",
            ".github/workflows/ci.yml contains inline `steps:` — "
            "per [GH-REPO-074] the canonical CI workflow MUST NOT contain "
            "inline job-step definitions; delegate via `uses:` to a "
            "centralized reusable workflow.",
        )
        findings += 1
    if not JOB_USES.search(text):
        emit(
            repo,
            "GH-REPO-074",
            ".github/workflows/ci.yml does not reference any reusable via "
            "`uses:` — per [GH-REPO-074] thin callers MUST delegate to a "
            "centralized reusable workflow (e.g., "
            "`uses: <layer>/.github/.github/workflows/swift-ci.yml@main`).",
        )
        findings += 1
    findings += check_ci_030(repo, text)
    findings += check_ci_059(repo, text)
    return findings


def check_forbidden_standalone(repo: str, workflows_dir: Path) -> int:
    """Per [GH-REPO-074] post-2026-05-10 consolidation: per-package
    `swift-format.yml` and `swiftlint.yml` MUST NOT exist standalone.
    """
    findings = 0
    for fname in ("swift-format.yml", "swiftlint.yml"):
        fpath = workflows_dir / fname
        if fpath.is_file():
            emit(
                repo,
                "GH-REPO-074",
                f".github/workflows/{fname} exists as a standalone file — "
                f"per [GH-REPO-074] (post-2026-05-10 consolidation) the "
                f"format and lint legs are absorbed into the layer "
                f"wrapper's universal matrix via swift-ci.yml. Delete the "
                f"standalone file.",
            )
            findings += 1
    return findings


def main(repo: str, repo_root: str) -> int:
    root = Path(repo_root)
    if not (root / "Package.swift").is_file():
        return 0  # not a per-package repo per [GH-REPO-074] scope
    workflows = root / ".github" / "workflows"
    if not workflows.is_dir():
        return 0
    findings = 0
    ci_yml = workflows / "ci.yml"
    if ci_yml.is_file():
        findings += check_ci_yml(repo, ci_yml)
    findings += check_forbidden_standalone(repo, workflows)
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-thin-callers.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
