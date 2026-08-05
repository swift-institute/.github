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

  [CI-059]      LAYER-ORG-hosted consumers: every per-repo `ci.yml` job that
                invokes an intra-Institute reusable workflow MUST carry
                `secrets: inherit` in the same job. Explicit per-secret
                forwarding (`secrets: { NAME: ... }` or `secrets:` block
                form) is forbidden once the underlying secret is org-level
                per [CI-060]. Omission is forbidden per shape-uniformity
                ([CI-031]) — even consumers whose dependency graph is fully
                public carry `secrets: inherit` as a single canonical shape.

                SUB-ORG-hosted consumers ([CI-059] sub-org caveat, pattern
                (ii), principal-confirmed 2026-06-04): the INVERSE. Their
                hop 1 into the parent layer wrapper is cross-org, where
                `secrets: inherit` silently delivers no org secrets per
                [CI-109]. Sub-org callers MUST explicit-forward the named
                private-dep credential set (PRIVATE_REPO_TOKEN,
                SWIFT_INSTITUTE_BOT_APP_CLIENT_ID, SWIFT_INSTITUTE_BOT_APP_ID,
                SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY) as
                `NAME: ${{ secrets.NAME }}` lines — values resolve in the
                consumer's own org context and survive the cross-org hop.
                `secrets: inherit` and omission both fire; a block missing
                any of the four names fires naming the missing ones; a
                block forwarding ANY name beyond the four fires as wider
                than the closed set.

                Principal-ruled contract (#92, 2026-07-30; enforced per
                #108): same-org caller -> layer wrapper uses
                `secrets: inherit` with explicit per-secret sets
                forbidden; cross-org callers use exactly the closed
                four-secret set; no other shapes. Exceptions exist only
                as typed whitelist entries with exact repository + path
                scope (CI_059_EXEMPTIONS below): an entry admits exactly
                one finding class in exactly one file, emitted as
                CI-059-EXEMPT (informational), and suppresses nothing
                else. Findings carry a [finding-class] tag so a reader
                knows which predicate fired.

                Owner detection: the org component of the repo argument.
                Fixture override: a `.fixture-sub-org-owner` marker file at
                the fixture root (content = simulated owner, default
                swift-ietf) lets the harness's fixed `swift-institute-test/`
                owner exercise the sub-org branch (same convention family as
                validate-sub-org-wrappers' `.github-as-sub-org` marker).

  INTEGRATED-DOCS-ADMISSION (Task 4-01 → TX10, swift-institute/.github#276;
                not a numbered [CI-NNN] rule — no /promote-rule pilot slot
                claimed by this task):

                TX10 deleted the temporary `integrated-docs` migration
                input from the universal reusable and every layer wrapper.
                A caller whose `ci:` job still carries the key in `with:`
                (ANY value) fires: GitHub rejects an undeclared input at
                run time, so its presence is a live breakage, not a style
                nit. Absence — the terminal shape of every caller — is not
                a finding.

Both CI-030 and CI-059 inherit the GH-REPO-074 file-level carve-out: workflows
that are themselves reusables (`on: workflow_call:`) are exempt — the rules
constrain *callers* to centralized reusables, not the reusables themselves.

Detection shape: line-anchored regex against the workflow YAML plus an
indentation-tracking per-job iterator for [CI-059] (which needs same-job
co-presence of `uses:` and `secrets: inherit`). Diagnostic precedence adds a
PyYAML parse gate through the repository's existing `validate_lib` helper; an
unparseable workflow can still emit broad diagnostics but cannot suppress one.

Diagnostic precedence: when a canonical, completely parsed `jobs:` mapping
contains only inline jobs and no job-level reusable-workflow `uses:`, the
absence-of-reusable diagnostic is the [GH-REPO-074] root. Correcting that root
requires replacing every inline job with a reusable caller, which necessarily
removes the same jobs' `runs-on:` and `steps:` keys. The two secondary
diagnostics are therefore omitted only for that proven shape. Mixed,
non-canonical, partial, and unparsed shapes retain independent diagnostics.
Finding frequency is deliberately absent from the precedence predicate.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path
from typing import Iterator, Tuple

from validate_lib import require_yaml


yaml = require_yaml()

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
DIRECT_JOB_RUNS_ON = re.compile(r"^    runs-on:", re.MULTILINE)
DIRECT_JOB_STEPS = re.compile(r"^    steps:\s*(#.*)?$", re.MULTILINE)
DIRECT_JOB_USES = re.compile(r"^    uses:\s+\S+", re.MULTILINE)

# Per-authority sub-orgs (11 L2 + 2 L3 per [CI-004b]). Their consumers'
# hop 1 (consumer -> parent layer wrapper) is cross-org, so [CI-059]'s
# requirement inverts for them per the sub-org caveat: explicit-forward
# the named credential set instead of `secrets: inherit` ([CI-109]).
SUB_ORGS = frozenset({
    "swift-ietf", "swift-iso", "swift-w3c", "swift-whatwg", "swift-ecma",
    "swift-incits", "swift-ieee", "swift-iec", "swift-arm-ltd",
    "swift-intel", "swift-riscv", "swift-linux-foundation",
    "swift-microsoft",
})

# The named private-dep credential set sub-org callers MUST forward.
# Principal-ruled CLOSED on #92 (2026-07-30): cross-org callers forward
# exactly this set — a block missing a name fires, and a block carrying
# any name beyond it fires ("wider than the closed set"). Widening the
# set is a ruling, not an edit.
REQUIRED_SUBORG_SECRETS = (
    "PRIVATE_REPO_TOKEN",
    "SWIFT_INSTITUTE_BOT_APP_CLIENT_ID",
    "SWIFT_INSTITUTE_BOT_APP_ID",
    "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
)

# ── Typed [CI-059] exemptions (#92 ruling: "exceptions exist only as
# typed whitelist entries with exact repository + path scope") ──
# Key: (owner/name, workflow path). Value: the ONE finding class the
# entry admits, plus the ruling that admitted it. An exemption suppresses
# exactly that class in exactly that file — every other class in the same
# file still fires — and the suppressed finding is emitted as
# CI-059-EXEMPT (informational; the aggregation layer counts only exact
# CI-059 rows). Adding a production entry requires a principal ruling.
#
# Finding classes: same-org-explicit, same-org-omitted, cross-org-inherit,
# cross-org-missing-names, cross-org-extra-names, cross-org-omitted.
#
# The swift-institute-test entry is fixture-scoped: the fixture harness
# runs every fixture as `swift-institute-test/<name>`, an owner no
# production sweep ever passes, so the entry can admit nothing outside
# the fixture suite. It exists so the exemption path has a failing
# control (an admitted shape, plus a near-miss that must still fire).
CI_059_EXEMPTIONS: dict[tuple[str, str], tuple[str, str]] = {
    ("swift-institute-test/swift-exempt-explicit-caller", ".github/workflows/ci.yml"): (
        "same-org-explicit",
        "fixture-scoped mechanism control; not a production ruling",
    ),
}


def _suborg_secret_line(name: str) -> re.Pattern[str]:
    """`NAME: ${{ secrets.NAME }}` line (any indent, optional comment)."""
    escaped = re.escape(name)
    return re.compile(
        rf"^\s+{escaped}:\s*\$\{{\{{\s*secrets\.{escaped}\s*\}}\}}\s*(#.*)?$",
        re.MULTILINE,
    )


SUBORG_SECRET_LINES = {
    name: _suborg_secret_line(name) for name in REQUIRED_SUBORG_SECRETS
}


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def _emit_ci_059(repo: str, finding_class: str, message: str) -> int:
    """Emit a classified [CI-059] finding through the typed-exemption gate.

    Returns the finding count (0 when a typed exemption admits exactly
    this class for exactly this repo + path; the row is then emitted as
    CI-059-EXEMPT, which the aggregation layer does not count). An
    exemption never suppresses a different class in the same file.
    """
    entry = CI_059_EXEMPTIONS.get((repo, ".github/workflows/ci.yml"))
    if entry is not None and entry[0] == finding_class:
        emit(
            repo,
            "CI-059-EXEMPT",
            f"[{finding_class}] admitted by typed exemption ({entry[1]}): {message}",
        )
        return 0
    emit(repo, "CI-059", f"[{finding_class}] {message}")
    return 1


def _forwarded_secret_names(job_body: str) -> list[str]:
    """Keys of the job's block-form `secrets:` mapping, in order.

    Indentation-tracked: children are the contiguous run of more-indented
    `NAME:` lines after a bare `secrets:` opener; the first line at or
    below the opener's indent closes the block.
    """
    names: list[str] = []
    block_indent: int | None = None
    for line in job_body.split("\n"):
        stripped = line.strip()
        if block_indent is not None:
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            if indent > block_indent:
                key = re.match(r"([A-Za-z0-9_-]+):", stripped)
                if key:
                    names.append(key.group(1))
                continue
            block_indent = None
        if re.match(r"^\s+secrets:\s*(#.*)?$", line):
            block_indent = len(line) - len(line.lstrip())
    return names


def _with_block_value(job_body: str, key: str) -> str | None:
    """Value of `key` inside the job's block-form `with:` mapping, as raw
    (unquoted-if-bare) text, or None if `with:` or the key is absent.

    Same indentation-tracked scan as `_forwarded_secret_names`, generalized
    to any key rather than only `secrets:`'s children.
    """
    block_indent: int | None = None
    for line in job_body.split("\n"):
        stripped = line.strip()
        if block_indent is not None:
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            if indent > block_indent:
                m = re.match(rf"{re.escape(key)}:\s*(.+?)\s*(#.*)?$", stripped)
                if m:
                    return m.group(1).strip()
                continue
            block_indent = None
        if re.match(r"^\s+with:\s*(#.*)?$", line):
            block_indent = len(line) - len(line.lstrip())
    return None


def check_integrated_docs_admission(repo: str, text: str) -> int:
    """INTEGRATED-DOCS-ADMISSION (Task 4-01 → TX10,
    swift-institute/.github#276): the temporary `integrated-docs` input
    was deleted at TX10, so a caller's `ci:` job carrying the key in
    `with:` (any value) is a live undeclared-input breakage. See the
    module docstring's INTEGRATED-DOCS-ADMISSION section.
    """
    findings = 0
    for job_name, job_body in iter_jobs(text):
        if job_name != "ci":
            continue
        value = _with_block_value(job_body, "integrated-docs")
        if value is None:
            continue  # absence is the terminal shape — not a finding
        emit(
            repo,
            "INTEGRATED-DOCS-ADMISSION",
            f".github/workflows/ci.yml 'ci' job `with: integrated-docs: {value}` "
            f"— TX10 (swift-institute/.github#276) deleted this temporary "
            f"migration input from the universal reusable and every layer "
            f"wrapper; GitHub rejects an undeclared input, so this caller "
            f"fails at run time. Regenerate it with generate-caller.py.",
        )
        findings += 1
    return findings


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


def has_complete_canonical_jobs_mapping(
    text: str, jobs: list[Tuple[str, str]]
) -> bool:
    """Whether `iter_jobs` accounted for one canonical `jobs:` mapping.

    The precedence proof is intentionally narrower than the validator's
    broad regex diagnostics. Any alias, inline mapping, malformed boundary,
    non-canonical indentation, duplicate `jobs:` key, or content before the
    first parsed job makes the proof fail closed so independent findings are
    retained.
    """
    lines = text.split("\n")
    starts = [
        index
        for index, line in enumerate(lines)
        if re.match(r"^jobs:\s*(#.*)?$", line)
    ]
    if len(starts) != 1 or not jobs:
        return False

    parsed_job_count = 0
    in_job = False
    for line in lines[starts[0] + 1 :]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(stripped)
        if indent == 2:
            if not JOB_NAME_LINE.match(stripped):
                return False
            parsed_job_count += 1
            in_job = True
            continue
        if indent < 4 or not in_job:
            return False

    return parsed_job_count == len(jobs)


def yaml_jobs_mapping_matches_parsed_jobs(
    text: str, jobs: list[Tuple[str, str]]
) -> bool:
    """Whether PyYAML confirms the same complete job mapping.

    Textual indentation proof alone cannot establish YAML parseability. This
    second gate fails closed on syntax errors, non-mapping documents/jobs,
    aliases that resolve to non-mapping jobs, duplicate job names, or any
    textual/parser disagreement about the job set.
    """
    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError:
        return False
    if not isinstance(document, dict):
        return False
    parsed_jobs = document.get("jobs")
    if not isinstance(parsed_jobs, dict):
        return False
    job_names = [name for name, _ in jobs]
    return (
        list(parsed_jobs) == job_names
        and len(parsed_jobs) == len(jobs)
        and all(isinstance(parsed_jobs[name], dict) for name in job_names)
    )


def gh_repo_074_no_reusable_root_supersedes_inline(text: str) -> bool:
    """Prove that the no-reusable root necessarily repairs inline keys.

    This is diagnostic factoring, not a change to [GH-REPO-074]. The rule's
    obligations remain independent in mixed workflows. Suppression is allowed
    only when every parsed job is an inline job, no job-level reusable caller
    exists, and every broad-regex inline match is exactly a direct key of those
    parsed jobs. Prevalence and repository identity are not inputs.
    """
    jobs = list(iter_jobs(text))
    if not has_complete_canonical_jobs_mapping(text, jobs):
        return False
    if not yaml_jobs_mapping_matches_parsed_jobs(text, jobs):
        return False
    if JOB_USES.search(text) or any(
        DIRECT_JOB_USES.search(body) for _, body in jobs
    ):
        return False
    if not all(
        DIRECT_JOB_RUNS_ON.search(body) and DIRECT_JOB_STEPS.search(body)
        for _, body in jobs
    ):
        return False

    parsed_runs_on = sum(
        len(DIRECT_JOB_RUNS_ON.findall(body)) for _, body in jobs
    )
    parsed_steps = sum(len(DIRECT_JOB_STEPS.findall(body)) for _, body in jobs)
    all_runs_on = len(INLINE_RUNS_ON.findall(text))
    all_steps = len(INLINE_STEPS.findall(text))
    return (
        parsed_runs_on + parsed_steps > 0
        and parsed_runs_on == all_runs_on
        and parsed_steps == all_steps
    )


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


def check_ci_059(repo: str, text: str, owner: str) -> int:
    """Check [CI-059]: layer-org callers MUST carry `secrets: inherit`;
    sub-org callers MUST explicit-forward the named credential set
    (the [CI-059] sub-org caveat per [CI-109] cross-org secret transport)."""
    if owner in SUB_ORGS:
        return _check_ci_059_suborg(repo, text)
    findings = 0
    for job_name, job_body in iter_jobs(text):
        if not USES_INTRA_INSTITUTE.search(job_body):
            continue  # job doesn't invoke an intra-Institute reusable
        if HAS_SECRETS_INHERIT.search(job_body):
            continue  # CI-059 satisfied
        # Job invokes intra-Institute reusable AND lacks `secrets: inherit`.
        # Distinguish explicit-forwarding from omission for a clearer message.
        if HAS_SECRETS_BLOCK.search(job_body) or HAS_SECRETS_INLINE_MAP.search(job_body):
            findings += _emit_ci_059(
                repo,
                "same-org-explicit",
                f".github/workflows/ci.yml job `{job_name}` invokes an "
                f"intra-Institute reusable with explicit `secrets:` "
                f"forwarding — per the #92 ruling same-org callers MUST use "
                f"`secrets: inherit`; explicit per-secret sets are forbidden. "
                f"Org-level secrets per [CI-060] obviate explicit forwarding, "
                f"which drifts at every new secret addition.",
            )
        else:
            findings += _emit_ci_059(
                repo,
                "same-org-omitted",
                f".github/workflows/ci.yml job `{job_name}` invokes an "
                f"intra-Institute reusable without `secrets: inherit` — per "
                f"[CI-059] and the #92 ruling every same-org `uses:` "
                f"invocation of an intra-Institute reusable MUST include "
                f"`secrets: inherit` (single canonical shape per [CI-031], "
                f"universal across consumers regardless of dependency-graph "
                f"visibility).",
            )
    return findings


def _check_ci_059_suborg(repo: str, text: str) -> int:
    """Sub-org branch of [CI-059]: explicit-forward of the named credential
    set required; `secrets: inherit` and omission both fire ([CI-109])."""
    findings = 0
    for job_name, job_body in iter_jobs(text):
        if not USES_INTRA_INSTITUTE.search(job_body):
            continue
        if HAS_SECRETS_INHERIT.search(job_body):
            findings += _emit_ci_059(
                repo,
                "cross-org-inherit",
                f".github/workflows/ci.yml job `{job_name}` is sub-org-hosted "
                f"and uses `secrets: inherit` — per the #92 ruling this hop "
                f"is cross-org and inherit silently delivers no org secrets "
                f"([CI-109]). Replace with the explicit `secrets:` block "
                f"forwarding {', '.join(REQUIRED_SUBORG_SECRETS)} as "
                f"`NAME: ${{{{ secrets.NAME }}}}` lines.",
            )
            continue
        if HAS_SECRETS_BLOCK.search(job_body) or HAS_SECRETS_INLINE_MAP.search(job_body):
            missing = [
                name
                for name in REQUIRED_SUBORG_SECRETS
                if not SUBORG_SECRET_LINES[name].search(job_body)
            ]
            if missing:
                findings += _emit_ci_059(
                    repo,
                    "cross-org-missing-names",
                    f".github/workflows/ci.yml job `{job_name}` is "
                    f"sub-org-hosted and explicit-forwards secrets but is "
                    f"missing {', '.join(missing)} — per the #92 ruling the "
                    f"closed credential set MUST be forwarded in full "
                    f"(`NAME: ${{{{ secrets.NAME }}}}` per name; [CI-109]).",
                )
            extra = [
                name
                for name in _forwarded_secret_names(job_body)
                if name not in REQUIRED_SUBORG_SECRETS
            ]
            if extra:
                findings += _emit_ci_059(
                    repo,
                    "cross-org-extra-names",
                    f".github/workflows/ci.yml job `{job_name}` is "
                    f"sub-org-hosted and forwards {', '.join(extra)} beyond "
                    f"the closed set — per the #92 ruling the cross-org "
                    f"transport is exactly "
                    f"{', '.join(REQUIRED_SUBORG_SECRETS)}; widening it is a "
                    f"ruling, not a caller edit.",
                )
            continue
        findings += _emit_ci_059(
            repo,
            "cross-org-omitted",
            f".github/workflows/ci.yml job `{job_name}` is sub-org-hosted "
            f"and invokes an intra-Institute reusable without any `secrets:` "
            f"— per the #92 ruling it MUST explicit-forward "
            f"{', '.join(REQUIRED_SUBORG_SECRETS)} ([CI-109]; inherit is "
            f"same-org-only and omission leaves resolve uncredentialed).",
        )
    return findings


def check_ci_yml(repo: str, ci_path: Path) -> int:
    """Validate `<repo>/.github/workflows/ci.yml` against thin-caller rules."""
    try:
        text = ci_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    if is_workflow_call(text):
        return 0  # tool-reusable carve-out (file-level, applies to all rules)
    # Owner drives the [CI-059] layer-org vs sub-org branch. Production:
    # the org component of the repo argument. Fixtures: the harness passes
    # a fixed `swift-institute-test/` owner, so a `.fixture-sub-org-owner`
    # marker at the fixture root overrides (content = simulated owner;
    # empty file defaults to swift-ietf).
    owner = repo.split("/", 1)[0]
    marker = ci_path.parent.parent.parent / ".fixture-sub-org-owner"
    if marker.is_file():
        owner = marker.read_text(encoding="utf-8").strip() or "swift-ietf"
    findings = 0
    no_reusable_root_supersedes_inline = (
        gh_repo_074_no_reusable_root_supersedes_inline(text)
    )
    if INLINE_RUNS_ON.search(text) and not no_reusable_root_supersedes_inline:
        emit(
            repo,
            "GH-REPO-074",
            ".github/workflows/ci.yml contains inline `runs-on:` — "
            "per [GH-REPO-074] this MUST be a thin caller delegating to a "
            "centralized reusable workflow via `uses:`. Reference shape: "
            "swift-carrier-primitives/.github/workflows/ci.yml.",
        )
        findings += 1
    if INLINE_STEPS.search(text) and not no_reusable_root_supersedes_inline:
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
    findings += check_ci_059(repo, text, owner)
    findings += check_integrated_docs_admission(repo, text)
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
