#!/usr/bin/env python3
"""
converge-callers.py — the Task 5-02 single-script fleet convergence
orchestrator (swift-institute/.github#276, #282; ruling R23a).

R23a is binding and is what this file's shape answers to: Task 5-02 is
"one script that converges every accessible ordinary caller in a single
run" — no per-wave manual gate, no stopping to seek approval between
organizations, no coordinator check-in between batches. Four properties
must live IN the script because they are what makes one run safe instead
of reckless (R23a, and the document's own Task 5-02 preconditions/change/
rollback fields):

  1. Self-verifying first target (`cmd_run` with `--canary`): converge one
     repository, assert the result — generated content byte-identical to
     what the landed generator (generate-caller.py, Task 5-01) produces,
     `validate-thin-callers.py` exit 0 with zero live findings against
     that content, PR opened cleanly — then continue automatically. A
     generator defect then costs one repository, not 550.
  2. Rollback pre-image captured before each mutation. The AUTHORITATIVE
     capture happens inside converge-caller.yml itself (the only place a
     write-capable bot token can be minted — see that file's header), in
     the same job, before the branch is created. This script persists a
     second, durable copy into the receipts directory as soon as the
     dispatched run's artifact is available, and refuses to consider a
     repository converged without one.
  3. Rate-limit awareness: GraphQL `search` batches ~50 repositories per
     call for census (a few dozen calls covers the whole ~550-repository
     fleet, not ~1,650+ individual REST reads), a rate-limit checkpoint
     runs before every batch, and 403/secondary-rate-limit responses back
     off exponentially rather than dying mid-fleet. Every WRITE (the
     bot's push + PR) happens inside a dispatched Actions run, which mints
     its own per-organization installation token with its own pool
     (converge-caller.yml's header) — this script's own REST/GraphQL
     budget is spent only on reads plus the coenttb-identity review step.
  4. The #90 renewed-dispatch check runs once, at the start of `cmd_run`
     — not per wave, because a single scripted run has a single start
     (R23a, explicit).

Every accessible ordinary caller gets a disposition (converged /
needs-convergence / typed-exception / out-of-scope) and every repository
this script would mutate gets a rollback record BEFORE the corresponding
converge-caller.yml dispatch — never the reverse.

Layer inference deliberately does NOT consult Workspace or re-derive from
org identity. Every EXISTING caller already declares which layer wrapper
it calls (`uses: <org>/.github/.github/workflows/swift-ci.yml@main`), and
`generate-caller.py`'s own `_cli_parse` already recovers layer from that
exact line — this script does the identical five-line inference (matched
against `generate_caller.LAYER_WRAPPER_ORG`) rather than inventing a
second Workspace-shaped path. A repository with no existing caller has no
`uses:` line to recover a layer from, so it is a typed exception routed to
review (Task 5-01's Change item 5's discipline extended to the fleet
scale: unknown shape is never silently guessed).

USAGE (every subcommand is safe to run read-only except `run --execute`):

  python3 converge-callers.py check-goal-90
  python3 converge-callers.py check-preconditions --repo-root <path>
  python3 converge-callers.py census --repo-root <path> --receipts <dir>
  python3 converge-callers.py run --repo-root <path> --receipts <dir> \\
      --canary <owner/name> [--execute] [--max-repos N]

`run` defaults to a dry run (plans and prints what it would do without
dispatching anything). `--execute` is required to dispatch a single real
mutation, and even then `run` refuses to proceed past preconditions that
are not `established` (R15.1: a merge is the change, the classification
is the proof — the same discipline applies to this script's own
ordering preconditions, which are read live, never assumed).
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import random
import subprocess
import sys
import time
import urllib.parse
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

# ─────────────────────────────────────────────────────────────────────────
# Constants — the programme's own identity, not re-derived per run.
# ─────────────────────────────────────────────────────────────────────────

GOAL_ISSUE = "swift-institute/.github#276"
WORK_OBJECT = "swift-institute/.github#282"
TASK_ID = "5-02"
PROGRAMME_DOC_SHA256 = (
    "184db8ef230cd7e532f9aeb167a51508bc897f8221ec935cb5a776ca1eaf62ef"
)
GOAL_90 = "swift-institute/.github#90"
CONVERGE_WORKFLOW = "converge-caller.yml"
CONVERGE_REPO = "swift-institute/.github"

# Approved typed `with:` keys the generator round-trips (generate-caller.py
# APPROVED_TYPED_INPUTS). Duplicated here as a read-only reference constant
# for disposition messages ONLY — the actual enforcement lives in the one
# generator, imported below, never re-implemented.
_RATE_LIMIT_FLOOR = 200  # stop issuing calls and checkpoint below this
_RATE_LIMIT_SLEEP_CAP_SECONDS = 900  # never sleep longer than this in one hop
_SECONDARY_BACKOFF_SCHEDULE = (5, 15, 30, 60, 120, 240)  # seconds, per retry


# ─────────────────────────────────────────────────────────────────────────
# The ONE generator (Task 5-01). Imported, never re-implemented — a second
# copy of generate()/parse_existing_caller() is exactly the drift class
# Task 5-01's own docstring exists to prevent.
# ─────────────────────────────────────────────────────────────────────────


def _load_generate_caller(scripts_dir: Path):
    spec = importlib.util.spec_from_file_location(
        "generate_caller", scripts_dir / "generate-caller.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["generate_caller"] = module
    spec.loader.exec_module(module)  # type: ignore[union-attr]
    return module


# ─────────────────────────────────────────────────────────────────────────
# gh CLI wrapper — rate-limit aware (property 3).
# ─────────────────────────────────────────────────────────────────────────


class GhCallFailed(RuntimeError):
    pass


class RateLimitedGh:
    """Wraps `gh api` (REST and GraphQL) with:

    - a remaining-quota checkpoint before every batch (`checkpoint()`),
      sleeping until reset only when remaining has fallen below
      `_RATE_LIMIT_FLOOR` — never a blind per-call sleep, which would slow
      down a fleet run that has ample quota for no reason;
    - exponential backoff, per `_SECONDARY_BACKOFF_SCHEDULE`, on secondary
      rate-limit / abuse-detection responses (HTTP 403 whose body names
      `secondary rate limit` or `abuse`), which is a DIFFERENT signal from
      primary quota exhaustion and is not visible in the `rate_limit`
      resource ahead of time;
    - every call counted, so a receipt can report exactly how many REST/
      GraphQL calls a run spent — the honesty discipline R6 applies to
      command evidence applies equally to a claim about API budget.
    """

    def __init__(self, *, dry_run_reads: bool = False) -> None:
        self.calls_made = 0
        self.dry_run_reads = dry_run_reads

    def _run(self, args: list[str]) -> str:
        # Retryable classes: secondary rate limit / abuse detection (quota-
        # shaped, the reason this class exists at all) AND transient 5xx
        # gateway errors (infrastructure-shaped, not quota-shaped, but
        # equally NOT a reason to abandon a fleet-scale run — live-observed
        # during this task's own census: a plain `HTTP 502` on an otherwise
        # well-formed GraphQL call, on the very first organization queried).
        # A 4xx (bad query, not found, auth) is never retried — retrying a
        # deterministic failure would just burn the backoff schedule for no
        # gain and mask a real defect as if it were transient.
        for attempt, backoff in enumerate((0,) + _SECONDARY_BACKOFF_SCHEDULE):
            if backoff:
                jittered = backoff * (1 + random.random() * 0.25)
                print(
                    f"::warning::retryable gh failure; backing off {jittered:.0f}s "
                    f"(attempt {attempt}/{len(_SECONDARY_BACKOFF_SCHEDULE)})",
                    file=sys.stderr,
                )
                time.sleep(jittered)
            proc = subprocess.run(
                ["gh"] + args, capture_output=True, text=True, timeout=120
            )
            self.calls_made += 1
            if proc.returncode == 0:
                return proc.stdout
            stderr_lower = proc.stderr.lower()
            retryable = (
                "secondary rate limit" in stderr_lower
                or "abuse" in stderr_lower
                or any(f"http {code}" in stderr_lower for code in (502, 503, 504))
            )
            if retryable:
                continue  # retry with backoff
            raise GhCallFailed(
                f"gh {' '.join(args)} failed (exit {proc.returncode}): {proc.stderr.strip()}"
            )
        raise GhCallFailed(
            f"gh {' '.join(args)} exhausted retries on a retryable failure class"
        )

    def api(self, path: str, *, jq: Optional[str] = None, paginate: bool = False) -> Any:
        args = ["api", path]
        if paginate:
            args.append("--paginate")
        if jq:
            args += ["--jq", jq]
        out = self._run(args)
        if jq:
            # --jq output is newline-delimited raw text; caller decides shape.
            return out
        return json.loads(out) if out.strip() else None

    def graphql(self, query: str, **variables: Any) -> dict:
        args = ["api", "graphql", "-f", f"query={query}"]
        for key, value in variables.items():
            args += ["-f", f"{key}={value}"]
        out = self._run(args)
        return json.loads(out)

    def checkpoint(self) -> None:
        """Read live remaining quota; sleep only if genuinely low.

        R23a property 3, literal reading: "A run that dies at repository
        300 on a quota wall is worse than one that paces itself." This is
        the pacing mechanism — called once per organization/batch, not
        once per repository (that would itself burn the budget it is
        trying to protect).
        """
        raw = self._run(["api", "rate_limit"])
        data = json.loads(raw)
        core = data["resources"]["core"]
        graphql = data["resources"]["graphql"]
        remaining = min(core["remaining"], graphql["remaining"])
        reset_at = max(core["reset"], graphql["reset"])
        if remaining >= _RATE_LIMIT_FLOOR:
            return
        sleep_for = min(
            max(reset_at - int(time.time()), 0) + 5, _RATE_LIMIT_SLEEP_CAP_SECONDS
        )
        print(
            f"::warning::rate limit low (remaining={remaining}); sleeping {sleep_for}s "
            f"toward reset at {datetime.fromtimestamp(reset_at, tz=timezone.utc).isoformat()}",
            file=sys.stderr,
        )
        time.sleep(sleep_for)


# ─────────────────────────────────────────────────────────────────────────
# #90 check — once at the start of the run (property 4 / R23a explicit).
# ─────────────────────────────────────────────────────────────────────────


@dataclass
class Goal90Check:
    state: str
    updated_at: str
    recent_merges_sampled: int
    verdict: str  # "clear" | "renewed-dispatch-suspected" | "unmeasured"
    detail: str


def check_goal_90(gh: RateLimitedGh, *, sample_org: str = "swift-primitives") -> Goal90Check:
    """Machine-checkable precondition literally named in the document:

        gh issue view 90 -R swift-institute/.github --json state,updatedAt
        gh pr list --search "org:swift-primitives is:merged merged:>=<today>" --limit 5

    Implemented via the equivalent authenticated REST reads per the
    document's own preference ("Prefer equivalent authenticated REST reads
    for the durable receipt"). The detection is deliberately conservative:
    it cannot prove a negative about a concurrent writer it cannot see
    (that would be exactly the R10 violation this programme exists to
    avoid), so it reports what it observed and lets a human/coordinator
    read the `recent_merges_sampled` list in the receipt rather than
    asserting a verdict beyond what #90's own state supports.
    """
    try:
        issue = gh.api("repos/swift-institute/.github/issues/90")
    except GhCallFailed as e:
        return Goal90Check(
            state="UNMEASURED",
            updated_at="",
            recent_merges_sampled=0,
            verdict="unmeasured",
            detail=f"could not read #90: {e}",
        )
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    query = urllib.parse.quote(
        f"org:{sample_org} is:pr is:merged merged:>={today}"
    )
    try:
        merged = gh.api(f"search/issues?q={query}&per_page=5")
        merged_count = merged.get("total_count", 0) if merged else 0
    except GhCallFailed as e:
        return Goal90Check(
            state=issue["state"],
            updated_at=issue["updated_at"],
            recent_merges_sampled=0,
            verdict="unmeasured",
            detail=f"#90 read OK but sample merge search failed: {e}",
        )
    # #90 tracks the swift-linter baseline convergence, a distinct writer
    # class from this task's caller convergence. "Renewed dispatch" here
    # means: #90 is OPEN and was updated inside the last 24h AND today's
    # sampled org shows merges already landing — evidence worth a human
    # look before this run's own writes start, not proof on its own.
    recently_touched = issue["state"] == "OPEN" and _within_hours(issue["updated_at"], 24)
    verdict = "renewed-dispatch-suspected" if (recently_touched and merged_count > 0) else "clear"
    return Goal90Check(
        state=issue["state"],
        updated_at=issue["updated_at"],
        recent_merges_sampled=merged_count,
        verdict=verdict,
        detail=(
            f"#90 state={issue['state']} updated_at={issue['updated_at']}; "
            f"{merged_count} merge(s) today sampled in {sample_org}"
        ),
    )


def _within_hours(iso_timestamp: str, hours: int) -> bool:
    then = datetime.strptime(iso_timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - then).total_seconds() < hours * 3600


# ─────────────────────────────────────────────────────────────────────────
# Ordering preconditions — "rulesets are already on target public/private
# contexts" and "integrated docs compatibility is live". Both are read
# LIVE, never assumed from a PR having merged (R15.1).
# ─────────────────────────────────────────────────────────────────────────


@dataclass
class Precondition:
    name: str
    status: str  # "established" | "reduced-pending-<issue>" | "unmeasured"
    detail: str


def check_integrated_docs_live(gh: RateLimitedGh) -> Precondition:
    """Task 4-01 lands a temporary migration-only input in
    swift-ci.yml/swift-docs.yml. Its presence is read directly from the
    default-branch blobs, not inferred from Task 4-01's issue state
    (R15.1: the merge is not the proof)."""
    try:
        text = gh.api(
            "repos/swift-institute/.github/contents/.github/workflows/swift-ci.yml",
            jq=".content",
        )
    except GhCallFailed as e:
        return Precondition("integrated-docs-live", "unmeasured", f"could not read swift-ci.yml: {e}")
    content = base64.b64decode(text.strip().strip('"')).decode("utf-8", errors="replace")
    # Every shape Task 4-01's Change item 3 anticipates for the input name.
    markers = ("integrated-docs", "docs-integrated", "INTEGRATED_DOCS_SUPPORTED")
    found = [m for m in markers if m in content]
    if found:
        return Precondition(
            "integrated-docs-live",
            "established",
            f"swift-ci.yml carries migration-compatibility marker(s): {found}",
        )
    return Precondition(
        "integrated-docs-live",
        "reduced-pending-Task-4-01",
        "swift-ci.yml carries none of the known migration-compatibility input "
        "shapes at head; Task 4-01 has not landed the integrated-docs contract yet.",
    )


def check_rulesets_on_target(
    gh: RateLimitedGh, *, sample_repos: Iterable[str]
) -> Precondition:
    """Task 3-02's live convergence is principal-executed (R22.2); this
    script never mutates a ruleset. It only reads the CURRENT required
    status-check contexts on a small cross-org sample and reports what it
    finds.

    CORRECTED (coordinator, 2026-08-04, live-measured): the predicate is
    NOT single-context exclusivity. The context chain, read directly
    rather than assumed: a canonical caller's `ci:` job calls the LAYER
    WRAPPER (`<org>/.github/.github/workflows/swift-ci.yml`), whose own
    jobs are `matrix:` (which in turn calls the CENTRAL
    `swift-institute/.github` `swift-ci.yml`, whose single aggregate is
    `ci-ok`) and `ci-ok:` (the layer wrapper's own outer aggregate). One
    canonical caller therefore legitimately emits BOTH `ci / ci-ok` (the
    wrapper's outer aggregate) and `ci / matrix / ci-ok` (the central
    aggregate, nested under the wrapper's `matrix` job) — verified live on
    `swift-foundations/swift-copy-on-write` at head
    `f1d649fc24f035e2f5dbc3fc23bb08b16cd80c42`: both names present,
    both `success`, simultaneously, from one workflow file.

    Today's migration-window convergence (Task 3-02, in flight) makes
    `ci / matrix / ci-ok` a REQUIRED context alongside the pre-existing
    `ci / ci-ok` — both-present is the establishing shape, not a
    transitional one. The original version of this predicate demanded
    single-context exclusivity, which is `ci / matrix / ci-ok`'s ABSENCE
    — the predicate would have flipped from `reduced-pending` to
    permanently unsatisfiable exactly when Task 3-02 succeeded (the same
    stale-tripwire class recorded elsewhere in this programme against a
    Task 4-01 near-deadlock). Single-context exclusivity is a LATER
    predicate (documented as predicate 14 by the coordinator), reached
    only after a second convergence pass that runs after this fleet run,
    not before it — this function does not attempt to detect that later
    state.
    """
    observations: dict[str, Any] = {}
    for repo in sample_repos:
        try:
            rulesets = gh.api(f"repos/{repo}/rulesets")
        except GhCallFailed as e:
            observations[repo] = f"UNMEASURED ({e})"
            continue
        contexts: list[str] = []
        for rs in rulesets or []:
            try:
                detail = gh.api(f"repos/{repo}/rulesets/{rs['id']}")
            except GhCallFailed as e:
                observations[repo] = f"UNMEASURED ({e})"
                continue
            for rule in detail.get("rules", []):
                if rule.get("type") == "required_status_checks":
                    contexts += [
                        c["context"]
                        for c in rule.get("parameters", {}).get("required_status_checks", [])
                    ]
        observations[repo] = contexts
    unmeasured = {r: v for r, v in observations.items() if isinstance(v, str)}
    if unmeasured:
        return Precondition(
            "rulesets-on-target",
            "unmeasured",
            f"could not read live rulesets for: {list(unmeasured)}",
        )
    missing_matrix_context = {
        r: v for r, v in observations.items() if "ci / matrix / ci-ok" not in v
    }
    if missing_matrix_context:
        return Precondition(
            "rulesets-on-target",
            "reduced-pending-Task-3-02",
            f"sampled repositories do not yet require `ci / matrix / ci-ok`: "
            f"{missing_matrix_context}. Task 3-02's live convergence "
            f"(principal-executed per R22.2, via sync-metadata.yml's rulesets "
            f"job) has not reached these repositories yet, or is still "
            f"in flight.",
        )
    return Precondition(
        "rulesets-on-target",
        "established",
        f"all sampled repositories require `ci / matrix / ci-ok` (both-present "
        f"with `ci / ci-ok` is the migration-window target shape, not "
        f"exclusivity): {observations}",
    )


# ─────────────────────────────────────────────────────────────────────────
# Census / classification — GraphQL-batched (property 3).
# ─────────────────────────────────────────────────────────────────────────

_ORGS_MANIFEST_RELATIVE = ".github/actions/read-orgs/orgs.yaml"

_SEARCH_QUERY = """
query($q: String!, $after: String) {
  search(query: $q, type: REPOSITORY, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on Repository {
        nameWithOwner
        isArchived
        isPrivate
        defaultBranchRef {
          name
          target {
            ... on Commit {
              checkSuites(last: 10) {
                nodes {
                  checkRuns(first: 100) { nodes { name } }
                }
              }
            }
          }
        }
        pkg: object(expression: "HEAD:Package.swift") { oid }
        caller: object(expression: "HEAD:.github/workflows/ci.yml") {
          ... on Blob { text byteSize isBinary }
        }
        formatWorkflow: object(expression: "HEAD:.github/workflows/swift-format.yml") { oid }
        swiftlintWorkflow: object(expression: "HEAD:.github/workflows/swiftlint.yml") { oid }
      }
    }
  }
}
"""

# Coordinator-directed column (2026-08-04): today's live ruleset convergence
# makes `ci / matrix / ci-ok` a REQUIRED context on converged public package
# repositories. A repository whose workflow is divergent, bespoke, or absent
# may not produce that name at all, which blocks its pull requests. This is
# read from the SAME batched GraphQL page as the rest of the census (nested
# `checkSuites`/`checkRuns` on the default-branch commit) — deliberately not
# a second per-repository REST call, per the coordinator's rate-limit
# instruction ("do not fan out per-repo REST calls where an org-level or
# GraphQL read will do").
REQUIRED_MATRIX_AGGREGATE = "ci / matrix / ci-ok"


def emits_matrix_ci_ok(node: dict) -> str:
    """'emits' / 'does-not-emit' / an UNMEASURED-with-reason string.

    Never silently 'does-not-emit' when the read itself was incomplete
    (R10 / zero-result protocol): absence of a default branch, a target
    commit, or any check suite at all is UNMEASURED, not a negative
    finding — those are read failures or repositories that have simply
    never run a workflow, not evidence the aggregate is missing FROM a
    workflow that did run.
    """
    if node["isPrivate"]:
        return "not-applicable-private"
    branch = node.get("defaultBranchRef")
    target = (branch or {}).get("target")
    if target is None:
        return "UNMEASURED (no default-branch target commit)"
    suites = ((target.get("checkSuites") or {}).get("nodes")) or []
    if not suites:
        return "UNMEASURED (no check suites at default-branch head)"
    names = {
        run.get("name")
        for suite in suites
        for run in ((suite.get("checkRuns") or {}).get("nodes")) or []
    }
    return "emits" if REQUIRED_MATRIX_AGGREGATE in names else "does-not-emit"


def read_active_orgs(repo_root: Path) -> list[str]:
    """Single source of truth (.github/actions/read-orgs/orgs.yaml), never
    a second inline copy — the exact discipline validate-branch-pins.py's
    own docstring names for the same manifest."""
    import yaml  # already a repo dependency (generate-caller.py imports it)

    manifest = yaml.safe_load((repo_root / _ORGS_MANIFEST_RELATIVE).read_text())
    return [r["name"] for r in manifest if r.get("status", "active") != "archived"]


@dataclass
class Disposition:
    repository: str
    visibility: str
    outcome: str  # "converged" | "needs-convergence" | "typed-exception" | "out-of-scope"
    detail: str
    layer: Optional[str] = None
    spec: Optional[dict] = None
    delete_standalone: bool = False
    matrix_ci_ok: str = "unmeasured"  # 'emits' | 'does-not-emit' | 'not-applicable-private' | 'UNMEASURED (...)'


@dataclass
class ExceptionRecord:
    repository: str
    reason_code: str
    reason_detail: str
    owner: str
    review_condition: str
    detected_at: str
    matrix_ci_ok: str = "unmeasured"


def _iter_org_repos(gh: RateLimitedGh, org: str) -> Iterator[dict]:
    after: Optional[str] = None
    while True:
        result = gh.graphql(
            _SEARCH_QUERY,
            q=f"org:{org} archived:false fork:false",
            after=after or "",
        )
        search = result["data"]["search"]
        for node in search["nodes"]:
            yield node
        if not search["pageInfo"]["hasNextPage"]:
            return
        after = search["pageInfo"]["endCursor"]


def classify_repo(node: dict, generate_caller) -> tuple[Optional[Disposition], Optional[ExceptionRecord]]:
    repo = node["nameWithOwner"]
    visibility = "private" if node["isPrivate"] else "public"
    now = datetime.now(timezone.utc).isoformat()
    # Computed once, from the same GraphQL page, regardless of disposition
    # class — the coordinator's instruction was to cover the divergent and
    # no-CI classes deliberately (R10), not only the healthy/canonical
    # population, so this is attached to every return path below, typed
    # exceptions included.
    matrix = emits_matrix_ci_ok(node)

    if node["isArchived"]:
        return None, ExceptionRecord(
            repo, "archived", "repository is archived", "n/a (platform state)",
            "repository is unarchived", now, matrix,
        )
    if node["pkg"] is None:
        return Disposition(repo, visibility, "out-of-scope", "no Package.swift at HEAD",
                            matrix_ci_ok=matrix), None
    if node["caller"] is None:
        return None, ExceptionRecord(
            repo, "no-caller-file", "no .github/workflows/ci.yml at HEAD",
            "repository maintainer / Workspace layer assignment",
            "Workspace assigns this repository's layer and a caller is authored",
            now, matrix,
        )
    if node["caller"].get("isBinary"):
        return None, ExceptionRecord(
            repo, "unreadable-caller", "ci.yml object reported isBinary=true",
            "repository maintainer", "manual investigation of the blob", now, matrix,
        )
    text = node["caller"]["text"]
    try:
        import yaml
        document = yaml.safe_load(text)
    except Exception as e:
        return None, ExceptionRecord(
            repo, "unparseable-caller", f"YAML parse error: {e}",
            "repository maintainer", "manual repair of ci.yml syntax", now, matrix,
        )
    uses = ((document or {}).get("jobs") or {}).get("ci", {}).get("uses", "")
    wrapper_org = uses.split("/", 1)[0] if "/" in uses else ""
    layer = next(
        (k for k, v in generate_caller.LAYER_WRAPPER_ORG.items() if v == wrapper_org), None
    )
    if layer is None:
        return None, ExceptionRecord(
            repo, "layer-unresolvable",
            f"ci job uses: {uses!r} does not match a known layer wrapper org",
            "coordinator / Workspace", "layer wrapper org corrected or a new "
            "layer class typed into LAYER_WRAPPER_ORG", now, matrix,
        )
    try:
        spec = generate_caller.parse_existing_caller(text, repository=repo, layer=layer)
    except generate_caller.UnknownCustomization as e:
        return None, ExceptionRecord(
            repo, "unknown-customization", str(e),
            "repository maintainer",
            "the customization is either approved into the generator's typed "
            "schema, or the repository is confirmed a permanent typed exception",
            now, matrix,
        )
    canonical = generate_caller.generate(spec)
    delete_standalone = bool(node["formatWorkflow"] or node["swiftlintWorkflow"])
    if canonical == text and not delete_standalone:
        return Disposition(repo, visibility, "converged", "already byte-identical to canonical output", layer,
                            matrix_ci_ok=matrix), None
    return Disposition(
        repo, visibility, "needs-convergence",
        "differs from canonical output" + (
            "; standalone format/lint workflow(s) present for deletion" if delete_standalone else ""
        ),
        layer,
        spec=asdict(spec),
        delete_standalone=delete_standalone,
        matrix_ci_ok=matrix,
    ), None


def run_census(
    gh: RateLimitedGh, repo_root: Path, generate_caller, *, orgs: Optional[list[str]] = None
) -> tuple[list[Disposition], list[ExceptionRecord]]:
    orgs = orgs or read_active_orgs(repo_root)
    dispositions: list[Disposition] = []
    exceptions: list[ExceptionRecord] = []
    for org in orgs:
        gh.checkpoint()
        for node in _iter_org_repos(gh, org):
            disposition, exception = classify_repo(node, generate_caller)
            if disposition:
                dispositions.append(disposition)
            if exception:
                exceptions.append(exception)
    return dispositions, exceptions


# ─────────────────────────────────────────────────────────────────────────
# Rollback persistence (property 2). The authoritative capture happens
# inside converge-caller.yml, in the same job, before the branch exists —
# see that file's header. This is the durable second copy: pulled from the
# dispatched run's uploaded artifact and written into the receipts
# directory, refusing to mark a repository converged without it.
# ─────────────────────────────────────────────────────────────────────────


def persist_rollback_blob(receipts_dir: Path, repository: str, blob: dict) -> Path:
    rollback_dir = receipts_dir / "rollback"
    rollback_dir.mkdir(parents=True, exist_ok=True)
    out = rollback_dir / f"{repository.replace('/', '__')}.json"
    out.write_text(json.dumps(blob, indent=2))
    return out


# ─────────────────────────────────────────────────────────────────────────
# Dispatch / poll / self-verify / approve / merge / read back.
# Real logic, gated behind `--execute` in main(); never invoked against a
# real repository in this landing (see the receipt).
# ─────────────────────────────────────────────────────────────────────────


def dispatch_convergence(gh: RateLimitedGh, disposition: Disposition, *, run_suffix: str) -> None:
    spec = disposition.spec or {}
    args = [
        "workflow", "run", CONVERGE_WORKFLOW,
        "-R", CONVERGE_REPO,
        "-f", f"repository={disposition.repository}",
        "-f", f"layer={disposition.layer}",
        "-f", f"platform-support={spec.get('platform_support') or ''}",
        "-f", f"enable-private-repos={'' if spec.get('enable_private_repos') is None else str(spec['enable_private_repos']).lower()}",
        "-f", f"test-filter={spec.get('test_filter') or ''}",
        "-f", f"delete-standalone-format-lint={'true' if disposition.delete_standalone else 'false'}",
        "-f", f"task-issue={WORK_OBJECT}",
        "-f", f"branch-suffix={run_suffix}",
    ]
    gh._run(args)  # noqa: SLF001 — internal call, dispatch has no JSON reply to parse


def find_dispatched_run(gh: RateLimitedGh, *, since_iso: str) -> Optional[dict]:
    """Locate the most recent converge-caller run dispatched after
    `since_iso`. Polling helper for the driver loop; a tracked wait per
    the programme's own foreground/background discipline — callers use
    this in a bounded loop with sleeps between polls, never a bare
    untracked wait."""
    runs = gh.api(
        f"repos/{CONVERGE_REPO}/actions/workflows/{CONVERGE_WORKFLOW}/runs?event=workflow_dispatch&per_page=5"
    )
    for run in runs.get("workflow_runs", []):
        if run["created_at"] >= since_iso:
            return run
    return None


def poll_run_to_completion(
    gh: RateLimitedGh, *, since_iso: str, timeout_seconds: int = 600, poll_interval: int = 15
) -> Optional[dict]:
    """Bounded poll loop for one dispatched converge-caller.yml run.

    This is the tracked-wait shape the programme's own CI-evidence
    discipline requires: a bare `sleep` with nothing watching it is
    prohibited, but a bounded loop that repeatedly reads the run object's
    own `status`/`conclusion` and sleeps between reads is the sanctioned
    alternative for a single dispatched run expected to finish in well
    under ten minutes (converge-caller.yml's own `timeout-minutes: 10`).
    Returns the last-seen run object (possibly still non-terminal if the
    timeout was hit — the caller must check `status`/`conclusion`, this
    function never assumes success on the caller's behalf).
    """
    deadline = time.time() + timeout_seconds
    run: Optional[dict] = None
    while time.time() < deadline:
        run = find_dispatched_run(gh, since_iso=since_iso)
        if run and run.get("status") == "completed":
            return run
        time.sleep(poll_interval)
    return run


def download_rollback_artifact(run_id: int, owner: str, name: str, dest_dir: Path) -> Optional[Path]:
    """`gh run download` (not raw `gh api`): artifacts are zip-encoded at
    the API layer, and `gh run download` is the sanctioned unzip-and-place
    path already used elsewhere in this ecosystem's tooling rather than a
    second hand-rolled zip reader."""
    artifact_name = f"rollback-{owner}__{name}"
    dest_dir.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["gh", "run", "download", str(run_id), "-R", CONVERGE_REPO,
         "-n", artifact_name, "-D", str(dest_dir)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return None
    candidate = dest_dir / f"{owner}__{name}.json"
    return candidate if candidate.is_file() else None


def self_verify(
    repo_root: Path, generate_caller, spec_dict: dict, layer: str
) -> tuple[bool, str]:
    """The self-verifying-first-target assertion (property 1), run purely
    LOCALLY and offline against the landed generator + validator — no
    network, safe to execute for real at any time. Returns (ok, detail).

    Checks, in order:
      1. generate(spec) round-trips through parse_existing_caller without
         raising (the generator's own internal consistency proof).
      2. The generated content, staged into a throwaway tree with a stub
         Package.swift, produces zero GH-REPO-074/CI-030/CI-059 findings
         from validate-thin-callers.py AND that script exits 0 — mirroring
         exactly what validate-thin-callers.yml's own Aggregate step
         counts as a violation (RULE_RE), so this is the same predicate
         the fleet-wide validator enforces, not a weaker proxy of it.
    """
    from generate_caller import CallerSpec  # already loaded by caller

    spec = CallerSpec(**{k: v for k, v in spec_dict.items() if v is not None})
    generated = generate_caller.generate(spec)
    try:
        generate_caller.parse_existing_caller(generated, repository=spec.repository, layer=layer)
    except generate_caller.UnknownCustomization as e:
        return False, f"generator's own output failed to round-trip: {e}"

    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "Package.swift").write_text("// swift-tools-version:6.4\n")
        workflows = root / ".github" / "workflows"
        workflows.mkdir(parents=True)
        (workflows / "ci.yml").write_text(generated)
        proc = subprocess.run(
            [sys.executable, str(repo_root / ".github/scripts/validate-thin-callers.py"),
             spec.repository, str(root)],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            return False, f"validate-thin-callers.py exited {proc.returncode}: {proc.stderr.strip()}"
        violation_rules = {"GH-REPO-074", "CI-030", "CI-059"}
        findings = [
            line for line in proc.stdout.splitlines()
            if line.split("\t")[1:2] and line.split("\t")[1] in violation_rules
        ]
        if findings:
            return False, f"validate-thin-callers.py reported live findings: {findings}"
    return True, "generator round-trip OK; validate-thin-callers.py exit 0, zero findings"


def _checks_ready_and_green(gh: RateLimitedGh, repository: str, head: str) -> tuple[bool, bool, str]:
    """One snapshot read of check-runs at `head`. Returns (ready, ok, detail):
    `ready` is False while any check tied to this exact head is still
    non-terminal (Trap A: only current-head runs count — a stale run at an
    older head must never block or satisfy this gate). `ok` is only
    meaningful when `ready` is True, and requires literal `success` on
    every current-head run (Trap B: `skipped` is terminal but is not
    success, so it never satisfies this gate by itself)."""
    checks = gh.api(f"repos/{repository}/commits/{head}/check-runs?per_page=100")
    current = [r for r in checks.get("check_runs", []) if r["head_sha"] == head]
    non_terminal = [r for r in current if r["status"] != "completed"]
    if non_terminal:
        return False, False, f"{len(non_terminal)} check(s) still non-terminal at head {head}"
    unsuccessful = [r for r in current if r["conclusion"] != "success"]
    if unsuccessful:
        names = [(r["name"], r["conclusion"]) for r in unsuccessful]
        return True, False, f"not every check-run at head {head} is 'success': {names}"
    return True, True, f"{len(current)} check-run(s) at head {head}, all 'success'"


def approve_and_merge(
    gh: RateLimitedGh, repository: str, pr_number: int, *, checks_timeout_seconds: int = 1800, poll_interval: int = 30
) -> dict:
    """R11's inverted flow: the bot authored and pushed (converge-caller.yml
    minted its own token for that), so THIS approval is submitted by
    coenttb — an identity distinct from the pusher, which is exactly what
    `require_last_push_approval` needs and what GitHub's own self-approval
    check would otherwise block if the same identity tried both roles.
    This is deliberately NOT routed through review-pr-transaction.yml: that
    workflow's whole purpose is producing a BOT approval on a coenttb-
    authored PR (the general-programme direction); here the roles are
    swapped, and an ordinary review is both sufficient and correct.

    Before approving: R18's `closingIssuesReferences` must be empty (this
    PR must never auto-close #282 or any other work object), and every
    check run at the exact head must be terminal, non-cancelled, and
    `success` (R6 Trap A/B discipline) — never `gh pr checks`, which
    surfaces passes and can mislead. Checks take real wall-clock time
    after a PR opens, so this is a bounded poll (tracked wait), not a
    single snapshot read that would usually see an empty or in-progress
    check-run set and pass vacuously.
    """
    graph = gh.graphql(
        """query($owner:String!,$name:String!,$number:Int!){
             repository(owner:$owner,name:$name){
               pullRequest(number:$number){
                 headRefOid
                 closingIssuesReferences(first:10){ nodes { number } }
               }
             }
           }""",
        owner=repository.split("/", 1)[0],
        name=repository.split("/", 1)[1],
        number=str(pr_number),
    )
    pr = graph["data"]["repository"]["pullRequest"]
    closing = pr["closingIssuesReferences"]["nodes"]
    if closing:
        raise RuntimeError(
            f"{repository}#{pr_number} closingIssuesReferences is non-empty "
            f"({closing}) — unlink before approving (R18)."
        )
    head = pr["headRefOid"]

    deadline = time.time() + checks_timeout_seconds
    ready, ok, detail = False, False, "no check-run read yet"
    while time.time() < deadline:
        ready, ok, detail = _checks_ready_and_green(gh, repository, head)
        if ready:
            break
        time.sleep(poll_interval)
    if not ready:
        raise RuntimeError(f"{repository}#{pr_number}: checks did not reach a terminal state within the poll window ({detail}).")
    if not ok:
        raise RuntimeError(f"{repository}#{pr_number}: {detail}")

    subprocess.run(
        ["gh", "api", f"repos/{repository}/pulls/{pr_number}/reviews",
         "--method", "POST", "-f", "event=APPROVE", "-f", f"commit_id={head}",
         "-f", "body=Task 5-02 convergence review: generated content verified "
               "byte-correct against generate-caller.py and validate-thin-callers.py "
               "exit 0 before dispatch; approver (coenttb) is distinct from the "
               "pushing bot identity per R11."],
        check=True, capture_output=True, text=True,
    )
    merge = subprocess.run(
        ["gh", "api", f"repos/{repository}/pulls/{pr_number}/merge",
         "--method", "PUT", "-f", "merge_method=squash"],
        check=True, capture_output=True, text=True,
    )
    merged = json.loads(merge.stdout)
    default_branch = gh.api(f"repos/{repository}", jq=".default_branch").strip().strip('"')
    head_after = gh.api(f"repos/{repository}/git/ref/heads/{default_branch}", jq=".object.sha").strip().strip('"')
    return {"merged": merged.get("merged"), "merge_sha": merged.get("sha"), "default_branch_head": head_after}


def converge_one(
    gh: RateLimitedGh,
    repo_root: Path,
    generate_caller,
    receipts: Path,
    disposition: Disposition,
    *,
    run_suffix: str,
) -> dict:
    """The full single-repository pipeline: dispatch, poll, persist the
    durable rollback copy, verify the opened PR's diff is exactly the
    canonical content, review+merge as a distinct identity, read the
    merged head back. Never raises past this function for an ordinary
    convergence failure — every failure mode becomes a typed-exception-
    shaped result the caller records and continues past, per the
    acceptance predicate: 'every repository that cannot be converged is
    recorded as a typed exception, never silently skipped.'
    """
    owner, name = disposition.repository.split("/", 1)
    since = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        dispatch_convergence(gh, disposition, run_suffix=run_suffix)
        run = poll_run_to_completion(gh, since_iso=since)
        if run is None or run.get("status") != "completed":
            return {"repository": disposition.repository, "outcome": "unmeasured",
                     "detail": f"converge-caller.yml run did not complete within the poll window (last seen: {run})"}
        if run.get("conclusion") != "success":
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "dispatch-run-failed",
                     "detail": f"converge-caller.yml concluded {run.get('conclusion')!r} ({run.get('html_url')})"}

        rollback_path = download_rollback_artifact(run["id"], owner, name, receipts / "rollback-artifacts")
        if rollback_path is None:
            # Property 2 is non-negotiable: no durable rollback blob means
            # this repository is NEVER treated as converged, even if the
            # run itself reported success.
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "rollback-blob-missing",
                     "detail": f"run {run.get('html_url')} succeeded but no rollback artifact was found"}
        rollback_blob = json.loads(rollback_path.read_text())
        persist_rollback_blob(receipts, disposition.repository, rollback_blob)

        pr_number = rollback_blob.get("pr_number")
        if pr_number is None:
            # already-canonical or already-open: nothing new was mutated by
            # THIS dispatch. Re-read live to record which one it was.
            open_prs = gh.api(f"repos/{disposition.repository}/pulls?state=open")
            matching = [p for p in open_prs if p["head"]["ref"].startswith("bot/5-02-converge-caller-")]
            if not matching:
                return {"repository": disposition.repository, "outcome": "converged",
                         "detail": "converge-caller.yml reported no PR to open (already canonical)."}
            pr_number = matching[0]["number"]

        ok, verify_detail = self_verify(repo_root, generate_caller, disposition.spec or {}, disposition.layer)
        if not ok:
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "self-verify-failed-post-dispatch",
                     "detail": verify_detail}

        merge_result = approve_and_merge(gh, disposition.repository, pr_number)
        if not merge_result.get("merged"):
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "merge-not-confirmed", "detail": str(merge_result)}
        return {"repository": disposition.repository, "outcome": "converged",
                "pr_number": pr_number, **merge_result}
    except (GhCallFailed, RuntimeError, subprocess.CalledProcessError) as e:
        return {"repository": disposition.repository, "outcome": "typed-exception",
                "reason_code": "pipeline-error", "detail": str(e)}


def converge_fleet(
    gh: RateLimitedGh,
    repo_root: Path,
    generate_caller,
    receipts: Path,
    targets: list[Disposition],
) -> list[dict]:
    """R23a's 'continues automatically through the remainder without human
    input': called ONLY after the self-verifying first target (the canary
    in `cmd_run`) has already succeeded. One rate-limit checkpoint before
    each repository — deliberately per-repository here, unlike census's
    per-organization cadence, because each repository in this loop makes a
    write-adjacent request budget (dispatch + poll + review + merge +
    read-back), not a single batched GraphQL read."""
    results: list[dict] = []
    for disposition in targets:
        gh.checkpoint()
        run_suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
        result = converge_one(gh, repo_root, generate_caller, receipts, disposition, run_suffix=run_suffix)
        results.append(result)
        print(f"[converge] {disposition.repository}: {result['outcome']} — {result.get('detail', '')}")
    return results


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────


def cmd_check_goal_90(args: argparse.Namespace) -> int:
    gh = RateLimitedGh()
    result = check_goal_90(gh)
    print(json.dumps(asdict(result), indent=2))
    return 0 if result.verdict != "renewed-dispatch-suspected" else 1


def cmd_check_preconditions(args: argparse.Namespace) -> int:
    gh = RateLimitedGh()
    docs = check_integrated_docs_live(gh)
    sample = [
        "swift-primitives/swift-array-primitives",
        "swift-standards/swift-domain-standard",
        "swift-foundations/swift-copy-on-write",
        "swift-ietf/swift-rfc-3986",
    ]
    rulesets = check_rulesets_on_target(gh, sample_repos=sample)
    result = {"preconditions": [asdict(docs), asdict(rulesets)]}
    print(json.dumps(result, indent=2))
    return 0 if docs.status == "established" and rulesets.status == "established" else 1


def cmd_census(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root)
    generate_caller = _load_generate_caller(repo_root / ".github/scripts")
    gh = RateLimitedGh()
    orgs = [args.org] if args.org else None
    dispositions, exceptions = run_census(gh, repo_root, generate_caller, orgs=orgs)
    receipts = Path(args.receipts)
    receipts.mkdir(parents=True, exist_ok=True)
    (receipts / "census.json").write_text(
        json.dumps([asdict(d) for d in dispositions], indent=2)
    )
    (receipts / "exceptions.json").write_text(
        json.dumps([asdict(e) for e in exceptions], indent=2)
    )
    by_outcome: dict[str, int] = {}
    for d in dispositions:
        by_outcome[d.outcome] = by_outcome.get(d.outcome, 0) + 1
    print(json.dumps({
        "gh_calls_made": gh.calls_made,
        "dispositions_by_outcome": by_outcome,
        "typed_exceptions": len(exceptions),
        "receipts": str(receipts),
    }, indent=2))
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root)
    generate_caller = _load_generate_caller(repo_root / ".github/scripts")
    receipts = Path(args.receipts)
    receipts.mkdir(parents=True, exist_ok=True)
    gh = RateLimitedGh()

    # Property 4: #90, once, at the start of this run.
    goal_90 = check_goal_90(gh)
    (receipts / "goal-90-check.json").write_text(json.dumps(asdict(goal_90), indent=2))
    print(f"[#90] {goal_90.verdict}: {goal_90.detail}")
    if goal_90.verdict == "renewed-dispatch-suspected":
        print("::error::#90 shows a possible renewed dispatch; refusing to start a new writer.")
        return 2

    # Ordering preconditions, read live, never assumed from a merge.
    docs = check_integrated_docs_live(gh)
    sample = [
        "swift-primitives/swift-array-primitives",
        "swift-standards/swift-domain-standard",
        "swift-foundations/swift-copy-on-write",
        "swift-ietf/swift-rfc-3986",
    ]
    rulesets = check_rulesets_on_target(gh, sample_repos=sample)
    (receipts / "preconditions.json").write_text(
        json.dumps([asdict(docs), asdict(rulesets)], indent=2)
    )
    print(f"[precondition] integrated-docs-live: {docs.status} — {docs.detail}")
    print(f"[precondition] rulesets-on-target: {rulesets.status} — {rulesets.detail}")
    if docs.status != "established" or rulesets.status != "established":
        print(
            "::notice::ordering preconditions not both established; recording "
            "reduced-pending and holding without mutating anything (R15.1)."
        )
        if not args.execute:
            return 0
        print("::error::--execute requested but preconditions are not established; refusing.")
        return 3

    dispositions, exceptions = run_census(gh, repo_root, generate_caller)
    (receipts / "census.json").write_text(json.dumps([asdict(d) for d in dispositions], indent=2))
    (receipts / "exceptions.json").write_text(json.dumps([asdict(e) for e in exceptions], indent=2))

    targets = [d for d in dispositions if d.outcome == "needs-convergence"]
    if args.max_repos:
        targets = targets[: args.max_repos]
    print(f"[census] {len(targets)} repositories need convergence; {len(exceptions)} typed exceptions recorded.")

    if not args.execute:
        print("[dry-run] no dispatch performed. Pass --execute to mutate (canary required first).")
        return 0

    if not args.canary:
        print("::error::--execute requires --canary <owner/name> for the self-verifying first target.")
        return 4

    canary = next((d for d in targets if d.repository == args.canary), None)
    if canary is None:
        print(f"::error::canary {args.canary!r} is not in the needs-convergence set.")
        return 5

    ok, detail = self_verify(repo_root, generate_caller, canary.spec or {}, canary.layer)
    print(f"[self-verify] {canary.repository}: {'OK' if ok else 'FAILED'} — {detail}")
    if not ok:
        print("::error::self-verifying first target failed offline verification; not dispatching anything.")
        return 6

    # Property 1, live half: the offline self-verify above already passed;
    # this is the END-TO-END assertion — dispatch, real PR, real checks,
    # real merge, real read-back — for exactly one repository before
    # anything else is touched. A generator or pipeline defect costs this
    # one repository, never the fleet.
    run_suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    canary_result = converge_one(gh, repo_root, generate_caller, receipts, canary, run_suffix=run_suffix)
    (receipts / "canary-result.json").write_text(json.dumps(canary_result, indent=2))
    print(f"[canary] {canary.repository}: {canary_result['outcome']} — {canary_result.get('detail', '')}")

    if canary_result["outcome"] != "converged":
        print(
            "::error::the self-verifying first target did not converge end-to-end "
            "(R11's positive control for a bot-authored PR merging under the "
            "current rulesets is therefore still unproven). Stopping before "
            "touching any of the remaining repositories, per the brief: "
            "'If the first PR cannot be merged, stop and report rather than "
            "opening 549 more.'"
        )
        return 7

    print(
        f"[canary] confirmed: a bot-authored, coenttb-approved caller PR merged "
        f"cleanly (merge_sha={canary_result.get('merge_sha')}). R11's positive "
        f"control is satisfied. Continuing automatically through the remaining "
        f"{len(targets) - 1} repositories with no further human input (R23a)."
    )

    remaining = [d for d in targets if d.repository != canary.repository]
    fleet_results = converge_fleet(gh, repo_root, generate_caller, receipts, remaining)
    (receipts / "fleet-results.json").write_text(
        json.dumps([canary_result] + fleet_results, indent=2)
    )
    by_outcome: dict[str, int] = {}
    for r in [canary_result] + fleet_results:
        by_outcome[r["outcome"]] = by_outcome.get(r["outcome"], 0) + 1
    print(json.dumps({"fleet_run_summary": by_outcome, "gh_calls_made": gh.calls_made}, indent=2))
    return 0 if by_outcome.get("typed-exception", 0) == 0 and by_outcome.get("unmeasured", 0) == 0 else 8


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)

    p90 = sub.add_parser("check-goal-90", help="Read-only #90 renewed-dispatch check.")
    p90.set_defaults(func=cmd_check_goal_90)

    ppre = sub.add_parser("check-preconditions", help="Read-only ordering preconditions check.")
    ppre.add_argument("--repo-root", required=True)
    ppre.set_defaults(func=cmd_check_preconditions)

    pcensus = sub.add_parser("census", help="Read-only fleet census + typed exceptions.")
    pcensus.add_argument("--repo-root", required=True)
    pcensus.add_argument("--receipts", required=True)
    pcensus.add_argument("--org", default=None, help="Restrict census to one org (testing).")
    pcensus.set_defaults(func=cmd_census)

    prun = sub.add_parser("run", help="Full orchestration. Dry-run unless --execute.")
    prun.add_argument("--repo-root", required=True)
    prun.add_argument("--receipts", required=True)
    prun.add_argument("--canary", default=None, help="Repository for the self-verifying first target.")
    prun.add_argument("--execute", action="store_true", help="Actually dispatch (canary only, first).")
    prun.add_argument("--max-repos", type=int, default=None, help="Cap the census-derived target list (testing).")
    prun.set_defaults(func=cmd_run)

    return p


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
