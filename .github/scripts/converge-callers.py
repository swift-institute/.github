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
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
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


class PreExistingRedError(RuntimeError):
    """A required context is red for a reason that has nothing to do with
    the converged caller — the target repository's own build/lint/tests
    were already failing before this run touched it (live example:
    swift-ietf/swift-rfc-3986#6's SwiftLint `superfluous_disable_command`,
    reproduced identically on unconverged `main`). Raised distinctly from
    plain `RuntimeError` so `converge_one()` records it as its own typed-
    exception reason_code (`blocked-by-pre-existing-red`) rather than
    lumping it in with a genuine caller/pipeline defect — coordinator
    instruction, 2026-08-05: 'a single undifferentiated failure count
    would make the fleet result unreadable.'"""


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
        # Bounded concurrency (coordinator instruction, 2026-08-05): every
        # `subprocess.run` call is independently thread-safe, but
        # `self.calls_made` is a shared counter multiple worker threads
        # increment concurrently — without a lock, concurrent `+= 1`s can
        # lose an update (read-modify-write race), which would silently
        # under-report the run's own honest call count (R6 applies to this
        # instrument's self-reporting too, not only to evidence commands).
        self._calls_made_lock = threading.Lock()

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
            with self._calls_made_lock:
                self.calls_made += 1
            if proc.returncode == 0:
                return proc.stdout
            stderr_lower = proc.stderr.lower()
            retryable = (
                "secondary rate limit" in stderr_lower
                or "abuse" in stderr_lower
                or any(f"http {code}" in stderr_lower for code in (502, 503, 504))
                # Live-caught, 2026-08-05: an empty or truncated response
                # body is a THIRD retryable class, distinct from both of
                # the above — it fails `gh`'s own JSON parse before any
                # status-based branch is reached, so it never carries an
                # HTTP code or a rate-limit phrase in stderr. Confirmed
                # not a quota signal (core/graphql both had thousands of
                # calls of headroom at the moment of failure) — this is
                # GitHub returning a genuinely incomplete body, which a
                # retry resolves the same way a 502 does. Never silently
                # return a short/partial result for this class: every
                # branch here either retries or raises, there is no
                # third path that swallows the error and returns
                # `proc.stdout` anyway.
                or "unexpected end of json input" in stderr_lower
                or "unexpected end of json" in stderr_lower
            )
            if retryable:
                continue  # retry with backoff
            raise GhCallFailed(
                f"gh {' '.join(args)} failed (exit {proc.returncode}): {proc.stderr.strip()}"
            )
        raise GhCallFailed(
            f"gh {' '.join(args)} exhausted retries on a retryable failure class "
            f"(cursor/args: {' '.join(args)})"
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
        """Every variable is sent via `-F` (typed), never `-f` (always
        string) — a real, live-caught defect: this method originally used
        `-f` uniformly, which silently stringifies everything, and a
        `$number: Int!` GraphQL variable sent as a JSON string is a hard
        `gh` CLI error ('Variable $number of type Int! was provided
        invalid value'), not a warning. `-F`'s "magic type conversion"
        (per `gh api --help`: literal `true`/`false`/`null` and
        integer-looking values convert; everything else stays a JSON
        string) makes it correct for BOTH typed and string GraphQL
        variables uniformly, so there is no need to track each variable's
        declared type here — verified directly: `-F owner=swift-primitives`
        still sends a JSON string, `-F number=11` sends a JSON integer.
        The query text itself stays on `-f` (`query=...` is never meant to
        be type-converted; it is Actions/GraphQL query TEXT, not a
        variable value).
        """
        args = ["api", "graphql", "-f", f"query={query}"]
        for key, value in variables.items():
            args += ["-F", f"{key}={value}"]
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


def _census_checkpoint_path(receipts: Path, org: str) -> Path:
    d = receipts / "census-checkpoint"
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{org}.json"


def _load_census_checkpoint(receipts: Path, org: str) -> dict:
    path = _census_checkpoint_path(receipts, org)
    if path.is_file():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            # A checkpoint file itself must never become a second source
            # of silent data loss — an unreadable checkpoint is treated
            # as absent (restart that ONE organization from page 1),
            # never as "done with nothing."
            pass
    return {"dispositions": [], "exceptions": [], "next_cursor": None, "done": False}


def _save_census_checkpoint(receipts: Path, org: str, state: dict) -> None:
    path = _census_checkpoint_path(receipts, org)
    # Write-then-rename: a process killed mid-write must never leave a
    # half-written, unparseable checkpoint file behind — that would
    # reintroduce exactly the "silent short page" failure mode this
    # checkpointing exists to remove, one layer up.
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(path)


def run_census(
    gh: RateLimitedGh,
    repo_root: Path,
    generate_caller,
    receipts: Path,
    *,
    orgs: Optional[list[str]] = None,
) -> tuple[list[Disposition], list[ExceptionRecord]]:
    """GraphQL-batched, checkpointed per organization AND per page.

    R23a property 3, extended by a live incident (2026-08-05): this is
    the THIRD time a full 17-organization census died partway through and
    had to restart from page 1 — expensive not because any single page is
    costly, but because the census is the mandatory first phase of every
    `cmd_run` invocation, so a death at organization 12 of 17 discards 11
    organizations' worth of already-good, already-paid-for work. Each
    page's classified results are persisted to
    `<receipts>/census-checkpoint/<org>.json` IMMEDIATELY after that page
    is fetched and classified — before the next `gh` call that could fail
    — and a fully-`done` organization is never re-fetched on a
    subsequent invocation with the same `--receipts` directory. The
    census is read-only and idempotent (this function mutates nothing on
    GitHub), so resuming from a checkpoint carries none of the staleness
    risk a resumed WRITE would.
    """
    orgs = orgs or read_active_orgs(repo_root)
    dispositions: list[Disposition] = []
    exceptions: list[ExceptionRecord] = []
    for org in orgs:
        gh.checkpoint()
        state = _load_census_checkpoint(receipts, org)
        if not state["done"]:
            after = state["next_cursor"] or ""
            while True:
                result = gh.graphql(
                    _SEARCH_QUERY,
                    q=f"org:{org} archived:false fork:false",
                    after=after,
                )
                search = result["data"]["search"]
                for node in search["nodes"]:
                    disposition, exception = classify_repo(node, generate_caller)
                    if disposition:
                        state["dispositions"].append(asdict(disposition))
                    if exception:
                        state["exceptions"].append(asdict(exception))
                if not search["pageInfo"]["hasNextPage"]:
                    state["done"] = True
                    state["next_cursor"] = None
                    _save_census_checkpoint(receipts, org, state)
                    break
                after = search["pageInfo"]["endCursor"]
                state["next_cursor"] = after
                # Checkpoint after EVERY page, not only at org completion —
                # this is the property that actually saves a partial
                # organization, not merely the ones already fully swept.
                _save_census_checkpoint(receipts, org, state)
        dispositions += [Disposition(**d) for d in state["dispositions"]]
        exceptions += [ExceptionRecord(**e) for e in state["exceptions"]]
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


def _load_rollback_blob(receipts_dir: Path, repository: str) -> Optional[dict]:
    """The read half of `persist_rollback_blob()` — same path convention.
    Lets `converge_one()` recover a repository's pre-image WITHOUT a fresh
    dispatch when resuming into an already-open PR from a prior, killed
    invocation of the same `--receipts` directory (coordinator
    instruction, 2026-08-05: durability across restarts is load-bearing,
    not merely within-run). An unreadable file is treated as absent, not
    fatal — the caller's own 'rollback-blob-missing-after-merge' outcome
    already exists to surface that honestly."""
    path = receipts_dir / "rollback" / f"{repository.replace('/', '__')}.json"
    if path.is_file():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return None
    return None


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


def _required_contexts(gh: RateLimitedGh, repository: str) -> list[str]:
    """Every `required_status_checks` context name across every ruleset on
    `repository`, read live — the same read `check_rulesets_on_target()`
    already performs, factored out so `_checks_ready_and_green()` can
    scope to it too."""
    contexts: list[str] = []
    rulesets = gh.api(f"repos/{repository}/rulesets") or []
    for rs in rulesets:
        detail = gh.api(f"repos/{repository}/rulesets/{rs['id']}")
        for rule in detail.get("rules", []):
            if rule.get("type") == "required_status_checks":
                contexts += [
                    c["context"]
                    for c in rule.get("parameters", {}).get("required_status_checks", [])
                ]
    return contexts


def _checks_ready_and_green(
    gh: RateLimitedGh, repository: str, head: str
) -> tuple[bool, bool, str, list[tuple[str, str]]]:
    """One snapshot read of check-runs at `head`, scoped to the
    repository's own live REQUIRED contexts — never "every check-run
    whatsoever."

    CORRECTED (2026-08-05, caught before re-firing rather than after):
    the original version required literal `success` on every check-run
    reported at the head, full stop. Every real matrix run in this fleet
    reports many LEGITIMATELY skipped legs (conditional platform/build
    variants that don't apply to a given event) and can carry unrelated
    advisory-leg failures (e.g. an experimental Embedded Wasm SDK build)
    that the ruleset itself does not require — observed live on
    `swift-primitives/swift-array-primitives#11`: both actual required
    contexts (`ci / ci-ok`, `ci / matrix / ci-ok`) `success`, while one
    unrelated advisory leg reports `failure` and ten legs report
    `skipped`. The original predicate would have refused to approve this
    (and structurally every other) PR in the fleet, never converging
    anything, for a reason that has nothing to do with mergeability. The
    ruleset's own required-context LIST is the authoritative scope, read
    live via `_required_contexts()` — never the full check-run set, and
    never a hardcoded name.

    Returns (ready, ok, detail, unsuccessful): `ready` is False while any
    REQUIRED context is missing at this exact head or still non-terminal
    (Trap A: only current-head runs count). `ok` is only meaningful when
    `ready` is True, and requires literal `success` on every REQUIRED
    context (Trap B: `skipped` is terminal but is not success, so a
    required context that skipped never satisfies this gate).
    `unsuccessful` is the exact `[(name, conclusion), ...]` list behind a
    `False` `ok` — empty whenever `ok` is `True` — so a caller can
    classify WHY without a second fetch: coordinator instruction,
    2026-08-05, distinguishing a target repository's own pre-existing red
    (a required context that ran to completion and genuinely failed,
    conclusion `failure`) from a structural caller/chain defect (anything
    else non-terminal-successful: `startup_failure`, `cancelled`,
    `timed_out`, `skipped`) is required so the fleet's own output stays
    readable rather than one undifferentiated failure count."""
    required = _required_contexts(gh, repository)
    if not required:
        return False, False, f"could not determine required status-check contexts for {repository} (empty ruleset read)", []
    checks = gh.api(f"repos/{repository}/commits/{head}/check-runs?per_page=100")
    current_by_name: dict[str, list[dict]] = {}
    for r in checks.get("check_runs", []):
        if r["head_sha"] == head:  # Trap A: stale-head runs neither block nor satisfy
            current_by_name.setdefault(r["name"], []).append(r)
    missing = [name for name in required if name not in current_by_name]
    if missing:
        return False, False, f"required context(s) not yet reported at head {head}: {missing}", []
    non_terminal = [
        (name, r["status"]) for name in required for r in current_by_name[name]
        if r["status"] != "completed"
    ]
    if non_terminal:
        return False, False, f"required check(s) still non-terminal at head {head}: {non_terminal}", []
    unsuccessful = [
        (name, r["conclusion"]) for name in required for r in current_by_name[name]
        if r["conclusion"] != "success"
    ]
    if unsuccessful:
        return True, False, f"not every REQUIRED check-run at head {head} is 'success': {unsuccessful}", unsuccessful
    return True, True, f"all {len(required)} required context(s) 'success' at head {head}: {required}", []


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
    ready, ok, detail, unsuccessful = False, False, "no check-run read yet", []
    while time.time() < deadline:
        ready, ok, detail, unsuccessful = _checks_ready_and_green(gh, repository, head)
        if ready:
            break
        time.sleep(poll_interval)
    if not ready:
        raise RuntimeError(f"{repository}#{pr_number}: checks did not reach a terminal state within the poll window ({detail}).")
    if not ok:
        # Classify WHY, per the coordinator's instruction (2026-08-05): a
        # required context that ran to completion and genuinely failed
        # (conclusion == "failure", every single one) is the target
        # repository's OWN pre-existing red — live example:
        # swift-ietf/swift-rfc-3986#6's SwiftLint failure, reproduced
        # identically on unconverged main. Anything else in the mix
        # (`startup_failure`, `cancelled`, `timed_out`, `skipped` on a
        # REQUIRED context) is treated as a structural caller/chain
        # defect and stays a plain RuntimeError — that class needs
        # investigation, not a shrug.
        if unsuccessful and all(conclusion == "failure" for _, conclusion in unsuccessful):
            raise PreExistingRedError(f"{repository}#{pr_number}: {detail}")
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
    try:
        # RESUME-BEFORE-DISPATCH (coordinator instruction, 2026-08-05):
        # a repository with an open, unmerged bot/5-02-* PR from a PRIOR,
        # possibly-killed invocation of this same `--receipts` directory
        # must be resumed, never re-dispatched. Checked FIRST — this is
        # also what makes restart cheap after a kill: no wasted
        # converge-caller.yml run for work a prior invocation already did.
        # The durable rollback record from that prior invocation is
        # recovered the same way (`_load_rollback_blob`, the read half of
        # `persist_rollback_blob`), so a resumed repository never loses
        # its pre-image just because this process didn't dispatch it.
        open_prs = gh.api(f"repos/{disposition.repository}/pulls?state=open")
        matching = [p for p in open_prs if p["head"]["ref"].startswith("bot/5-02-converge-caller-")]
        pr_number = matching[0]["number"] if matching else None
        rollback_blob = _load_rollback_blob(receipts, disposition.repository)

        if pr_number is not None:
            print(f"[resume] {disposition.repository}: reusing open PR #{pr_number} from a prior invocation, no new dispatch.")
        else:
            since = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            dispatch_convergence(gh, disposition, run_suffix=run_suffix)
            run = poll_run_to_completion(gh, since_iso=since)
            if run is None or run.get("status") != "completed":
                return {"repository": disposition.repository, "outcome": "unmeasured",
                         "detail": f"converge-caller.yml run did not complete within the poll window (last seen: {run})"}
            if run.get("conclusion") != "success":
                return {"repository": disposition.repository, "outcome": "typed-exception",
                         "reason_code": "dispatch-run-failed",
                         "detail": f"converge-caller.yml concluded {run.get('conclusion')!r} ({run.get('html_url')})"}

            # CORRECTED ORDERING (2026-08-05, live incident): find the actual
            # PR this dispatch produced FIRST, independent of whether the
            # rollback artifact can be downloaded. The original ordering
            # checked artifact availability before ever looking at the PR's
            # own state, so a download-path defect (a real one, fixed
            # separately in converge-caller.yml — `tr '/' '__'` silently
            # collapses to a single underscore, not the double underscore the
            # artifact's own NAME and this function both expect) masked a
            # genuine `startup_failure` on the caller's own CI behind an
            # unrelated, less alarming 'rollback-blob-missing' label. A
            # mislabelled failure is worse than a loud one: it looks like a
            # containable, well-understood exception class instead of what it
            # actually was, a fleet-wide outage. The rollback artifact is
            # still fetched here, but its absence is recorded and DEFERRED —
            # never allowed to stand in front of the PR's real check-run
            # verdict, which is authoritative and is read via
            # approve_and_merge() below regardless of artifact availability.
            open_prs = gh.api(f"repos/{disposition.repository}/pulls?state=open")
            matching = [p for p in open_prs if p["head"]["ref"].startswith("bot/5-02-converge-caller-")]
            pr_number = matching[0]["number"] if matching else None

            rollback_path = download_rollback_artifact(run["id"], owner, name, receipts / "rollback-artifacts")
            if rollback_path is not None:
                rollback_blob = json.loads(rollback_path.read_text())
                persist_rollback_blob(receipts, disposition.repository, rollback_blob)

            if pr_number is None:
                if rollback_blob is not None and rollback_blob.get("pr_number") is None:
                    # converge-caller.yml itself decided there was nothing to
                    # change (already-canonical) — a real, positive outcome,
                    # not a failure to find something that should exist.
                    return {"repository": disposition.repository, "outcome": "converged",
                             "detail": "already canonical; no PR opened."}
                return {"repository": disposition.repository, "outcome": "unmeasured",
                         "detail": f"run {run.get('html_url')} succeeded but no open bot/5-02-* PR and no "
                                   f"rollback record was found for this repository — genuinely inconclusive, "
                                   f"never silently folded into either 'converged' or a specific exception class."}

        ok, verify_detail = self_verify(repo_root, generate_caller, disposition.spec or {}, disposition.layer)
        if not ok:
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "self-verify-failed-post-dispatch",
                     "detail": verify_detail}

        # THE authoritative signal. approve_and_merge() polls the PR's own
        # check-runs with R6 Trap A/B discipline and raises naming the
        # EXACT conclusion (e.g. `startup_failure`, not a generic
        # 'checks failed') — this must run regardless of rollback-artifact
        # availability, which is exactly what the reordering above makes
        # true now.
        merge_result = approve_and_merge(gh, disposition.repository, pr_number)
        if not merge_result.get("merged"):
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "merge-not-confirmed", "detail": str(merge_result)}

        # Property 2 is still non-negotiable — it is evaluated LAST, not
        # first, so it can never again mask a real outcome, but a merge
        # with no recovered rollback blob is a genuine, distinctly
        # alarming finding in its own right (this repository's pre-image
        # is not recorded) and must not be silently treated as 'converged'.
        if rollback_blob is None:
            return {"repository": disposition.repository, "outcome": "typed-exception",
                     "reason_code": "rollback-blob-missing-after-merge",
                     "detail": f"{disposition.repository}#{pr_number} MERGED "
                               f"(merge_sha={merge_result.get('merge_sha')}) but no durable rollback blob "
                               f"was ever recovered — this repository's pre-image is NOT recorded; "
                               f"investigate reversibility before trusting it."}

        return {"repository": disposition.repository, "outcome": "converged",
                "pr_number": pr_number, **merge_result}
    except PreExistingRedError as e:
        # Distinct label, per the coordinator's instruction (2026-08-05):
        # this repository's own build/lint/tests were already broken
        # before this run touched it — not a defect in the generated
        # caller, and not something retrying would fix. Caught BEFORE the
        # general RuntimeError handler below (PreExistingRedError is a
        # RuntimeError subclass; Python matches except clauses in order).
        return {"repository": disposition.repository, "outcome": "typed-exception",
                "reason_code": "blocked-by-pre-existing-red", "detail": str(e)}
    except (GhCallFailed, RuntimeError, subprocess.CalledProcessError) as e:
        return {"repository": disposition.repository, "outcome": "typed-exception",
                "reason_code": "pipeline-error", "detail": str(e)}


def converge_fleet(
    gh: RateLimitedGh,
    repo_root: Path,
    generate_caller,
    receipts: Path,
    targets: list[Disposition],
    *,
    max_concurrency: int = 6,
) -> list[dict]:
    """R23a's 'continues automatically through the remainder without human
    input': called ONLY after the self-verifying first target (the canary
    in `cmd_run`) has already succeeded, alone, serially — concurrency
    applies only after that (coordinator instruction, 2026-08-05).

    BOUNDED CONCURRENCY, not unlimited fan-out. The dominant per-repository
    cost is wall-clock time waiting for that repository's own CI to
    complete — genuinely idle time from this process's point of view, not
    CPU or memory pressure — so running several repositories' pipelines
    concurrently is what takes a run that would otherwise need ~4.8
    minutes/repository serially (measured; ~465 repositories serially is
    on the order of 36 hours) inside a SINGLE process lifetime instead of
    needing dozens of restarts across a harness that has already been
    observed to kill a long-lived background process outright (a real
    incident: a prior invocation of this exact function died silently
    after ~62 minutes serial, leaving one PR opened but never reviewed).
    `max_concurrency` defaults to 6, the coordinator's own suggested
    figure, exposed as a parameter rather than hardcoded so it can be
    tuned without another code change.

    Each `disposition` is independent — different repository, different
    branch, different PR — so `converge_one()` needs no additional
    locking beyond what `RateLimitedGh` itself already provides
    (`_calls_made_lock` around the shared call counter). Results are
    collected in COMPLETION order, not submission order; every downstream
    consumer of this list aggregates by outcome/reason_code, never by
    position, so this does not lose information."""
    results: list[dict] = []
    if max_concurrency <= 1:
        for disposition in targets:
            gh.checkpoint()
            run_suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
            result = converge_one(gh, repo_root, generate_caller, receipts, disposition, run_suffix=run_suffix)
            results.append(result)
            print(f"[converge] {disposition.repository}: {result['outcome']} — {result.get('detail', '')}")
        return results

    with ThreadPoolExecutor(max_workers=max_concurrency) as pool:
        futures = {}
        for disposition in targets:
            gh.checkpoint()  # paced at submission time, not at completion
            run_suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f") + f"-{disposition.repository.replace('/', '-')}"
            future = pool.submit(
                converge_one, gh, repo_root, generate_caller, receipts, disposition, run_suffix=run_suffix
            )
            futures[future] = disposition
        for future in as_completed(futures):
            disposition = futures[future]
            try:
                result = future.result()
            except Exception as e:  # a worker thread must never silently vanish a repository
                result = {"repository": disposition.repository, "outcome": "typed-exception",
                          "reason_code": "pipeline-error", "detail": f"worker thread raised: {e}"}
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
    receipts = Path(args.receipts)
    receipts.mkdir(parents=True, exist_ok=True)
    dispositions, exceptions = run_census(gh, repo_root, generate_caller, receipts, orgs=orgs)
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

    dispositions, exceptions = run_census(gh, repo_root, generate_caller, receipts)
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
        # This message intentionally makes NO claim about R11's own
        # standing. R11 (a bot-authored PR can merge under the current
        # rulesets, with coenttb as the required distinct approver) is a
        # one-time historical fact once ANY canary has demonstrably
        # merged — swift-foundations/swift-copy-on-write#11, merge
        # 8e43e43cad71f45111e74f37fb875a9d0f68b63d, approved by coenttb at
        # 2026-08-05T00:49:35Z. A LATER canary failing (this one, or a
        # future one) never un-proves that; it means only that THIS run's
        # self-verifying first target did not converge, for whatever
        # reason logged above. An earlier version of this message
        # asserted "R11 ... is therefore still unproven" unconditionally
        # here, which became false the moment R11 was first proven and
        # would have told a future reader the opposite of what happened —
        # corrected live, 2026-08-05, coordinator-caught.
        print(
            "::error::the self-verifying first target did not converge end-to-end "
            "this run — see the logged outcome/detail above for the reason. "
            "Stopping before touching any of the remaining repositories, per the "
            "brief: 'If the first PR cannot be merged, stop and report rather "
            "than opening 549 more.'"
        )
        return 7

    print(
        f"[canary] confirmed: a bot-authored, coenttb-approved caller PR merged "
        f"cleanly (merge_sha={canary_result.get('merge_sha')}). R11's positive "
        f"control is satisfied. Continuing automatically through the remaining "
        f"{len(targets) - 1} repositories with no further human input (R23a)."
    )

    remaining = [d for d in targets if d.repository != canary.repository]
    print(f"[fleet] converging {len(remaining)} repositories with max_concurrency={args.max_concurrency}.")
    fleet_results = converge_fleet(
        gh, repo_root, generate_caller, receipts, remaining, max_concurrency=args.max_concurrency
    )
    all_results = [canary_result] + fleet_results
    (receipts / "fleet-results.json").write_text(json.dumps(all_results, indent=2))

    # Coordinator instruction (2026-08-05): "Do not let a repository's
    # pre-existing red be recorded as a convergence failure ... a single
    # undifferentiated failure count would make the fleet result
    # unreadable." by_outcome alone collapses every typed-exception into
    # one bucket; by_label further splits on reason_code so
    # "converged" / "blocked-by-pre-existing-red" (the target's own build
    # was already broken, not our defect) / every other typed-exception
    # class / unmeasured are each named and counted separately.
    by_outcome: dict[str, int] = {}
    by_label: dict[str, int] = {}
    for r in all_results:
        by_outcome[r["outcome"]] = by_outcome.get(r["outcome"], 0) + 1
        label = r["outcome"] if r["outcome"] != "typed-exception" else f"typed-exception / {r.get('reason_code', 'unlabelled')}"
        by_label[label] = by_label.get(label, 0) + 1
    print(json.dumps({
        "fleet_run_summary_by_outcome": by_outcome,
        "fleet_run_summary_by_label": by_label,
        "gh_calls_made": gh.calls_made,
    }, indent=2))
    genuine_problems = sum(
        count for label, count in by_label.items()
        if label != "converged" and label != "typed-exception / blocked-by-pre-existing-red"
    )
    return 0 if genuine_problems == 0 else 8


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
    prun.add_argument("--max-concurrency", type=int, default=6,
                       help="Repositories converged in flight simultaneously after the canary (default 6, "
                            "coordinator's own figure). 1 runs the original fully-serial loop.")
    prun.set_defaults(func=cmd_run)

    return p


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
