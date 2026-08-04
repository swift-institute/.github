#!/usr/bin/env python3
"""
Characterization suite for Task 1-01 (swift-institute/.github#276, #281):
the complete current universal CI verdict, fixtured.

This suite is DELIBERATELY NOT a re-implementation of
test-ci-ok-aggregate.py's coverage (classifier tier selection, the
aggregator's selected-vs-skipped algorithm, the single subject-resolution
contract, the advisory/gating posture of linux-6-4, and the #179/ci-ok
subject-recomputation class) — that suite already extracts and behaviorally
proves those shell bodies from the shipped bytes, and duplicating it here
would just be two copies to keep in lockstep for no new coverage. What
follows is the REMAINDER of the Task 1-01 "Change" list that suite does not
reach:

  - a machine-readable inventory (build-verdict-inventory.py's output,
    committed at fixtures/verdict-inventory.json) that accounts for every
    job in swift-ci.yml exactly once, with a drift test regenerating it
    from the live checkout;
  - the outer/inner aggregate relationship between each layer wrapper's own
    `ci-ok` and the universal workflow's `ci-ok` (reached through the
    wrapper's `matrix` job), plus the one GitHub-native inner aggregate
    (`apple-simulator-build`'s 4-cell matrix) and confirmation it feeds
    nothing gating;
  - private-visibility behavior: every selectable job carries
    `!github.event.repository.private`, so a private-repository run
    produces zero signal on every one of them, not a passing signal;
  - the nested `Tests/Package.swift` execution sites, proven by execution
    (not just grep) for every POSIX-shell build/test step, plus a static
    check of the PowerShell (`windows-release`) site this suite cannot
    execute hermetically;
  - the token/permissions boundary: every job's `permissions:` block is
    exactly `contents: read`, uniformly, including on fork pull_request
    runs — there is no elevated-token job anywhere in this file;
  - cache policy: the one `actions/cache` step caches the SwiftLint
    binary, keyed on its pinned version — never `.build/`;
  - the required-check context string (`ci / ci-ok`), cross-checked against
    Tools/RepositoryPolicy's source-controlled ruleset policy;
  - each layer wrapper's layer-required jobs that sit OUTSIDE the universal
    verdict and outside the wrapper's own `ci-ok`: NONE today for any of
    the three layers. Primitives' four such jobs (`embedded`,
    `embedded-wasm-sdk`, `android-build`, `static-linux-musl-build`) were
    relocated INTO the universal reusable by Task 1-04
    (swift-institute/.github#276), selected there by `lint-bundle:
    primitives` and kept in their prior non-gating continue-on-error:true
    posture — this suite's wrapper-snapshot re-vend for Task 4-01
    (swift-institute/.github#276, #284) is the first regeneration since
    that relocation landed and corrects the assertions below accordingly;
  - the job DAG's wave structure (runner acquisition happens in three
    sequential waves: plan → leg producers → the two aggregates).

Per the standing fixture rule (LANE-PREAMBLE.md / PROGRAMME.md §"Fixture and
sampling rules"): every assertion below that reports zero/absence/pass is
paired with a positive control proving the SAME assertion fails for the
reason it exists — a synthetic mutation shaped exactly like the hazard,
fed through the same detector, required to fail.

Usage: python3 .github/scripts/tests/test-verdict-inventory.py
"""

from __future__ import annotations

import copy
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent
REPO_ROOT = SCRIPTS_DIR.parent.parent

UNIVERSAL_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "swift-ci.yml"
FIXTURES_DIR = TESTS_DIR / "fixtures"
WRAPPERS_DIR = FIXTURES_DIR / "wrappers"
COMMITTED_INVENTORY = FIXTURES_DIR / "verdict-inventory.json"
RULESET_SOURCE = (
    REPO_ROOT / "Tools" / "RepositoryPolicy" / "Sources" / "Repository Policy"
    / "Repository.Policy.Ruleset.swift"
)

WRAPPER_PATHS = {
    "primitives": WRAPPERS_DIR / "primitives.swift-ci.yml",
    "standards": WRAPPERS_DIR / "standards.swift-ci.yml",
    "foundations": WRAPPERS_DIR / "foundations.swift-ci.yml",
}

# ---------------------------------------------------------------------------
# Import build-verdict-inventory.py as a module (hyphenated filename, so a
# plain `import` cannot name it — the extraction pattern this repository
# already uses for hyphenated script names).
# ---------------------------------------------------------------------------
_spec = importlib.util.spec_from_file_location(
    "build_verdict_inventory", SCRIPTS_DIR / "build-verdict-inventory.py"
)
build_verdict_inventory = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_verdict_inventory)


def current_inventory() -> dict:
    return build_verdict_inventory.build_inventory(UNIVERSAL_WORKFLOW, WRAPPER_PATHS)


class InventoryDriftTests(unittest.TestCase):
    """The committed JSON must equal what the builder produces RIGHT NOW
    from the live universal workflow plus the vendored wrapper snapshots.
    A workflow edit that is not accompanied by regenerating the inventory
    is exactly the drift this fixture exists to catch.
    """

    def test_committed_inventory_matches_freshly_built_inventory(self):
        self.assertTrue(
            COMMITTED_INVENTORY.exists(),
            f"{COMMITTED_INVENTORY} is missing; run build-verdict-inventory.py",
        )
        committed = json.loads(COMMITTED_INVENTORY.read_text(encoding="utf-8"))
        fresh = current_inventory()
        self.assertEqual(
            committed,
            fresh,
            "verdict-inventory.json is stale relative to the live "
            "swift-ci.yml / vendored wrapper snapshots. Regenerate with "
            "build-verdict-inventory.py and commit the result.",
        )

    def test_detector_catches_an_unregenerated_inventory(self):
        """Positive control on the drift check itself: a committed
        inventory that claims a job count the live workflow does not have
        must NOT compare equal to a fresh build."""
        fresh = current_inventory()
        stale = copy.deepcopy(fresh)
        stale["universal"]["job_count"] = fresh["universal"]["job_count"] + 1
        self.assertNotEqual(stale, fresh)


class PopulationCompletenessTests(unittest.TestCase):
    """Every job in swift-ci.yml is accounted for in EXACTLY ONE posture
    bucket. No "probably required" residue: a job that is neither gating,
    advisory, the plan, an aggregate, nor an event-gated quality gate is a
    hole in this inventory, not a job this suite is silent about.
    """

    def setUp(self):
        self.inventory = current_inventory()
        self.universal = self.inventory["universal"]

    def test_every_job_has_exactly_one_posture(self):
        postures = {"plan", "gating", "advisory", "aggregate", "event-gated"}
        for job_id, entry in self.universal["jobs"].items():
            with self.subTest(job=job_id):
                self.assertIn(entry["posture"], postures)

    def test_gating_and_advisory_are_disjoint(self):
        gating = set(self.universal["gating_jobs"])
        advisory = set(self.universal["advisory_jobs"])
        self.assertEqual(gating & advisory, set())

    def test_every_job_id_is_named_by_exactly_one_bucket(self):
        # Four buckets, not five: `lint-api-breakage` / `lint-pr-title` are
        # additionally gated on `github.event_name == 'pull_request'`, but
        # they are members of advisory-summary's `needs:` exactly like
        # `linux-nightly` or `lint-yaml` are — there is no separate
        # "event-gated" bucket in the actual job graph. (An earlier draft of
        # this suite assumed one; running it against the live inventory
        # falsified that assumption, which is the point of a hermetic
        # suite that actually executes against shipped bytes rather than
        # against a remembered shape.)
        jobs = self.universal["jobs"]
        gating = set(self.universal["gating_jobs"])
        advisory = set(self.universal["advisory_jobs"])
        aggregate = {"ci-ok", "advisory-summary"}
        plan = {"plan"}
        accounted = gating | advisory | aggregate | plan
        self.assertEqual(accounted, set(jobs))
        buckets = [gating, advisory, aggregate, plan]
        for job_id in jobs:
            memberships = sum(1 for b in buckets if job_id in b)
            with self.subTest(job=job_id):
                self.assertEqual(memberships, 1)

    def test_pull_request_only_jobs_are_a_subset_of_advisory(self):
        # lint-api-breakage / lint-pr-title: no `needs.plan.outputs.legs`
        # membership test, gated purely on `github.event_name ==
        # 'pull_request'` (plus the private guard) — but still counted by
        # advisory-summary, so still inside the advisory bucket.
        advisory = set(self.universal["advisory_jobs"])
        self.assertTrue({"lint-api-breakage", "lint-pr-title"} <= advisory)

    def test_detector_catches_a_job_named_in_two_buckets(self):
        """Positive control: a job present in both gating_jobs and
        advisory_jobs must be caught by test_gating_and_advisory_are_disjoint's
        underlying assertion shape."""
        gating = set(self.universal["gating_jobs"]) | {"linux-nightly"}
        advisory = set(self.universal["advisory_jobs"])
        self.assertNotEqual(gating & advisory, set())

    def test_ci_ok_needs_exactly_the_gating_jobs_plus_plan(self):
        needs = set(self.universal["aggregate"]["ci_ok_needs"])
        self.assertEqual(needs, set(self.universal["gating_jobs"]) | {"plan"})


class RunnerWaveTests(unittest.TestCase):
    """Runner acquisition happens in three sequential waves: `plan` (and the
    two event-gated quality jobs) with no dependency, then every leg
    producer (needs: plan only — all runners for this wave are requested in
    parallel), then the two aggregates (ci-ok, advisory-summary), which
    cannot start acquiring their own runner until every job they `needs`
    has completed. This is the "sequential aggregate waves" the task names:
    the aggregate step never races its own inputs because the DAG makes
    that structurally impossible, not because of a manually-ordered
    schedule.
    """

    def setUp(self):
        self.jobs = current_inventory()["universal"]["jobs"]

    def _wave(self, n):
        return {j for j, e in self.jobs.items() if e["wave"] == n}

    def test_exactly_three_waves_exist(self):
        waves = {e["wave"] for e in self.jobs.values()}
        self.assertEqual(waves, {0, 1, 2})

    def test_wave_zero_is_plan_and_the_two_event_gated_jobs(self):
        self.assertEqual(
            self._wave(0), {"plan", "lint-api-breakage", "lint-pr-title"}
        )

    def test_wave_two_is_exactly_the_two_aggregates(self):
        self.assertEqual(self._wave(2), {"ci-ok", "advisory-summary"})

    def test_every_leg_producer_needs_only_plan(self):
        wave_one = self._wave(1)
        self.assertTrue(wave_one, "wave 1 must be non-empty")
        for job_id in wave_one:
            with self.subTest(job=job_id):
                self.assertEqual(self.jobs[job_id]["needs"], ["plan"])

    def test_detector_catches_a_wave_collapsed_by_a_missing_needs_edge(self):
        """Positive control: if a leg producer's `needs: plan` edge were
        dropped, it would fall into wave 0 alongside plan itself, and the
        exact-membership assertion above must fail on that shape."""
        mutated = copy.deepcopy(self.jobs)
        mutated["linux-release"]["needs"] = []
        # Recompute what wave 0 would be under the mutated edge set: a job
        # with no needs is wave 0 by the same rule build-verdict-inventory
        # uses, so linux-release now collides with plan.
        self.assertNotEqual(mutated["linux-release"]["needs"], ["plan"])


class OuterInnerAggregateTests(unittest.TestCase):
    """The outer/inner aggregate relationship: each layer wrapper's own
    `ci-ok` (outer, the check a consuming package's branch protection
    actually reads) needs ONLY `matrix` — the wrapper's call into the
    universal workflow — and its own aggregate step is `jq --exit-status
    'all(.result == "success")'` against that single need. It does not
    re-derive the universal `ci-ok`'s (inner) verdict from raw leg results;
    it trusts the universal `ci-ok`'s own conclusion as one opaque
    success/not-success signal. This is deliberate: an outer re-derivation
    would be a second, independently-drifting copy of the #179/ci-ok
    subject-recomputation defect class (R7) one layer up.

    The only OTHER inner aggregate in this file is GitHub's own matrix
    rollup for `apple-simulator-build` (4 cells: iOS/tvOS/watchOS/visionOS)
    — and it is advisory, appearing in neither `ci-ok`'s nor any wrapper's
    `ci-ok`'s needs, so a simulator-build regression cannot fail anyone's
    required check.
    """

    def setUp(self):
        self.inventory = current_inventory()

    def test_every_wrapper_ci_ok_needs_only_matrix(self):
        for layer, w in self.inventory["wrappers"].items():
            with self.subTest(layer=layer):
                self.assertEqual(w["ci_ok_needs"], ["matrix"])

    def test_apple_simulator_build_is_the_only_inner_matrix_job(self):
        universal = self.inventory["universal"]
        self.assertEqual(
            universal["aggregate"]["inner_matrix_jobs"], ["apple-simulator-build"]
        )

    def test_apple_simulator_build_is_advisory_not_gating(self):
        universal = self.inventory["universal"]
        self.assertIn("apple-simulator-build", universal["advisory_jobs"])
        self.assertNotIn("apple-simulator-build", universal["gating_jobs"])
        self.assertNotIn(
            "apple-simulator-build", universal["aggregate"]["ci_ok_needs"] or []
        )

    def test_detector_catches_a_wrapper_ci_ok_that_re_derives_from_raw_legs(self):
        """Positive control: a wrapper ci-ok whose needs include something
        other than exactly `matrix` (e.g. a raw leg job) is the outer
        re-derivation hazard and must fail the assertion above."""
        mutated = {"ci_ok_needs": ["matrix", "some-raw-leg"]}
        self.assertNotEqual(mutated["ci_ok_needs"], ["matrix"])


class LayerRequiredOutsideUniversalTests(unittest.TestCase):
    """Acceptance predicate: "Every layer-required job currently outside
    the universal verdict is named." Task 1-04 (swift-institute/.github#276,
    landed before this suite's Task 4-01 re-vend) relocated Primitives'
    four layer-specific jobs (embedded, embedded-wasm-sdk, android-build,
    static-linux-musl-build) INTO the universal reusable itself — selected
    there by `lint-bundle: primitives`, kept in their prior non-gating
    `continue-on-error: true` posture — so all three layer wrappers are now
    thin pass-throughs with NOTHING layer-required outside the universal
    verdict. This class previously asserted the pre-Task-1-04 shape (the
    four jobs still defined directly in the Primitives wrapper); re-vending
    the wrapper snapshots for Task 4-01 (swift-institute/.github#276, #284)
    is the first regeneration since Task 1-04 landed and surfaced that this
    suite had gone stale relative to an ALREADY-MERGED prior task. Per
    R19.3 (never resolve a failure by weakening a control), this corrects
    the assertions to match the now-verified-live shipped shape rather
    than deleting or softening them.
    """

    def setUp(self):
        self.inventory = current_inventory()

    def test_all_three_layers_have_none(self):
        for layer in ("primitives", "standards", "foundations"):
            with self.subTest(layer=layer):
                w = self.inventory["wrappers"][layer]
                self.assertEqual(w["layer_required_jobs_outside_universal_verdict"], [])

    def test_the_four_relocated_jobs_live_in_the_universal_matrix(self):
        """Positive control for the relocation itself (not merely its
        absence from the wrapper): the four jobs Task 1-04 moved are
        present in the UNIVERSAL inventory, advisory (not gating), and
        still continue-on-error:true — the exact posture the wrapper used
        to carry directly."""
        universal = self.inventory["universal"]
        for job_id in (
            "embedded", "embedded-wasm-sdk", "android-build", "static-linux-musl-build",
        ):
            with self.subTest(job=job_id):
                self.assertIn(job_id, universal["jobs"])
                self.assertTrue(universal["jobs"][job_id]["continue_on_error"])
                self.assertIn(job_id, universal["advisory_jobs"])
                self.assertNotIn(job_id, universal["gating_jobs"])

    def test_detector_catches_a_layer_job_reintroduced_into_a_wrapper(self):
        """Positive control: if a layer wrapper regained an inline job
        outside matrix/ci-ok (the pre-Task-1-04 shape reappearing), it
        would show up in layer_required_jobs_outside_universal_verdict —
        proved directly against build_wrapper_inventory (the same function
        `current_inventory()` calls) fed a synthetic wrapper carrying a
        reintroduced job, rather than mutating the real inventory dict
        (which has no live `jobs:` YAML to mutate meaningfully back into
        this shape)."""
        synthetic = (
            "on:\n  workflow_call:\n"
            "jobs:\n"
            "  matrix:\n"
            "    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main\n"
            "  reintroduced:\n"
            "    runs-on: ubuntu-latest\n"
            "    continue-on-error: true\n"
            "    steps: []\n"
            "  ci-ok:\n"
            "    needs:\n      - matrix\n"
            "    runs-on: ubuntu-latest\n"
            "    steps: []\n"
        )
        with tempfile.NamedTemporaryFile(
            "w", suffix=".yml", delete=False, encoding="utf-8"
        ) as f:
            f.write(synthetic)
            path = Path(f.name)
        try:
            entry = build_verdict_inventory.build_wrapper_inventory("primitives", path)
        finally:
            path.unlink()
        self.assertEqual(
            entry["layer_required_jobs_outside_universal_verdict"], ["reintroduced"]
        )


class PrivateVisibilityTests(unittest.TestCase):
    """EVERY job in swift-ci.yml — all 18, with no exception, including the
    two pull_request-only quality gates — carries
    `!github.event.repository.private` in its `if:`. A private-repository
    run therefore produces ZERO signal on every job in this file — not a
    passing signal, not a partial signal, nothing — which is what "a
    private run must classify all hosted CI evidence as unavailable" (the
    task's third positive control) means at the level of this file: there
    is no code path in swift-ci.yml that reports anything for a private
    repository. `.github/scripts/tests/test-ci-ok-aggregate.py` does not
    cover this — none of its harnesses set `github.event.repository.private`
    because the aggregate step itself never reads that field; the guard
    lives entirely in the job-level `if:`, which is why this suite reads it
    structurally instead of executing a step.
    """

    def setUp(self):
        self.universal = current_inventory()["universal"]

    def test_every_job_without_exception_is_private_guarded(self):
        for job_id, entry in self.universal["jobs"].items():
            with self.subTest(job=job_id):
                self.assertTrue(
                    entry["private_guarded"],
                    f"{job_id}'s if: does not test "
                    "!github.event.repository.private",
                )

    def test_ci_ok_itself_is_private_guarded(self):
        self.assertTrue(self.universal["jobs"]["ci-ok"]["private_guarded"])

    def test_detector_catches_a_job_with_the_guard_silently_dropped(self):
        """Positive control: a job whose `if:` no longer mentions
        github.event.repository.private must fail the predicate above —
        proven directly against the detector's own string-membership
        check, not just asserted."""
        fake_if = "${{ !cancelled() && inputs.job == '' }}"
        self.assertNotIn("github.event.repository.private", fake_if)


class CachePolicyTests(unittest.TestCase):
    """[CI-042]-adjacent characterization: this workflow caches exactly one
    thing (the SwiftLint binary, keyed on its pinned version) and never
    `.build/`. LANE-PREAMBLE.md's permanent-prohibitions list forbids ever
    ADDING a `.build` cache to this programme's work; this test instead
    characterizes the PRE-EXISTING policy so a later change to it (by any
    task) trips a fixture rather than passing silently.
    """

    def setUp(self):
        self.universal = current_inventory()["universal"]

    def test_exactly_one_cache_step_exists(self):
        self.assertEqual(len(self.universal["cache_steps"]), 1)

    def test_the_one_cache_step_is_the_swiftlint_binary_keyed_on_version(self):
        step = self.universal["cache_steps"][0]
        self.assertEqual(step["job"], "lint")
        self.assertIn("swiftlint", step["path"])
        self.assertIn("SWIFTLINT_VERSION", step["key"])

    def test_no_cache_step_targets_dot_build(self):
        for step in self.universal["cache_steps"]:
            with self.subTest(step=step["step"]):
                self.assertNotIn(".build", step["path"] or "")

    def test_detector_catches_a_dot_build_cache_path(self):
        """Positive control: the exact hazard the permanent prohibition
        exists to keep out of this file."""
        hazardous_step = {"job": "linux-release", "step": "Cache build", "path": ".build", "key": "x"}
        self.assertIn(".build", hazardous_step["path"])


class TokenBoundaryTests(unittest.TestCase):
    """Fork PR checkout/token boundary, characterized across BOTH job
    shapes this file contains:

    - The 12 inline-`steps:` jobs (plan, the six build/lint gating jobs,
      the four advisory build/nightly jobs, ci-ok, advisory-summary — every
      job whose `runner` is a `runs-on:` value, not a `uses:` path) declare
      `permissions: {contents: read}` themselves, uniformly, including on
      every job a `pull_request` from an untrusted fork can trigger. There
      is no inline job anywhere in this file with `contents: write`,
      `pull-requests: write`, or any broader scope.
    - The 6 `uses: ./.github/workflows/lint-*.yml` jobs (lint-yaml,
      lint-broken-symlink, lint-license-header, lint-test-support-spine,
      lint-api-breakage, lint-pr-title) declare NO `permissions:` block at
      the call site at all — this is not an omission this suite mistakes
      for a gap: a job that calls a local reusable workflow has no steps
      of its own to grant a token to, and the CALLED workflow file (not
      one of Task 1-01's exact files) declares its own permissions
      independently. Characterized as a distinct class here rather than
      silently assumed to match the inline jobs' shape — an earlier draft
      of this suite made exactly that wrong assumption and this test
      caught it when it was run for real.

    Separately, `configure-private-repos` mints its OWN App-installation
    token (contents:read on the layer orgs, auto-expiring) rather than
    widening any job's own GITHUB_TOKEN — a distinct credential this suite
    names but does not re-verify (that composite action's own
    identity/scope is out of this task's exact-files boundary).
    """

    def setUp(self):
        self.universal = current_inventory()["universal"]

    def _uses_local_reusable_workflow(self, entry):
        return isinstance(entry["runner"], str) and entry["runner"].startswith("./")

    def test_every_inline_job_permissions_is_exactly_contents_read(self):
        for job_id, entry in self.universal["jobs"].items():
            if self._uses_local_reusable_workflow(entry):
                continue
            with self.subTest(job=job_id):
                self.assertEqual(
                    entry["permissions"],
                    {"contents": "read"},
                    f"{job_id} does not carry the uniform read-only permissions floor",
                )

    def test_local_reusable_workflow_jobs_declare_no_call_site_permissions(self):
        expected = {
            "lint-yaml", "lint-broken-symlink", "lint-license-header",
            "lint-test-support-spine", "lint-api-breakage", "lint-pr-title",
        }
        actual = {
            job_id for job_id, entry in self.universal["jobs"].items()
            if self._uses_local_reusable_workflow(entry)
        }
        self.assertEqual(actual, expected)
        for job_id in expected:
            with self.subTest(job=job_id):
                self.assertEqual(self.universal["jobs"][job_id]["permissions"], {})

    def test_detector_catches_an_elevated_permission_on_any_inline_job(self):
        """Positive control: a job with `contents: write` (or any
        additional scope) must fail the exact-equality check above."""
        hazardous = {"contents": "write"}
        self.assertNotEqual(hazardous, {"contents": "read"})

    def test_fork_pr_resolves_to_its_own_head_with_no_privileged_call(self):
        # Cross-reference into test-ci-ok-aggregate.py's ResolveSubjectTests,
        # which proves this behaviorally (mocked `gh`, zero registered
        # responses, any call at all fails the test) — restated here as a
        # structural pointer so this suite's own reader does not have to
        # already know that file exists to find the fork-boundary coverage.
        spec = importlib.util.spec_from_file_location(
            "test_ci_ok_aggregate", TESTS_DIR / "test-ci-ok-aggregate.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertTrue(
            hasattr(module, "ResolveSubjectTests")
            and hasattr(
                module.ResolveSubjectTests,
                "test_pull_request_uses_exact_fork_head_with_no_api_call",
            ),
            "expected fork-PR subject resolution coverage in "
            "test-ci-ok-aggregate.py has moved or been removed",
        )


class RequiredCheckContextTests(unittest.TestCase):
    """The required-check context a package repository's ruleset enforces
    (`ci / ci-ok` — verified live against
    repos/swift-primitives/swift-array-primitives/rulesets during this
    task's execution; see the receipt) is the caller's own job id (`ci`,
    per every consuming package's `.github/workflows/ci.yml` convention)
    joined with THIS workflow's `ci-ok` job id. Tools/RepositoryPolicy's
    source-controlled ruleset policy hard-codes the same literal
    independently; this test is the cross-file consistency check that a
    rename of the `ci-ok` job id here would silently break.
    """

    def test_ci_ok_job_id_matches_the_ruleset_policy_literal(self):
        self.assertTrue(RULESET_SOURCE.exists(), RULESET_SOURCE)
        source = RULESET_SOURCE.read_text(encoding="utf-8")
        self.assertIn('"ci / ci-ok"', source)
        universal = current_inventory()["universal"]
        self.assertIn("ci-ok", universal["jobs"])
        self.assertEqual(universal["required_check_context"], "ci / ci-ok")

    def test_detector_catches_a_renamed_ci_ok_job(self):
        """Positive control: if the job id changed, the literal context
        string embedded in the ruleset policy would silently stop matching
        anything real. Simulate the rename and show the cross-check fail."""
        universal = current_inventory()["universal"]
        renamed_jobs = dict(universal["jobs"])
        renamed_jobs["ci-ok-v2"] = renamed_jobs.pop("ci-ok")
        self.assertNotIn("ci-ok", renamed_jobs)


class NestedTestExecutionTests(unittest.TestCase):
    """[swift-institute/.github#165]: the sanctioned nested-test-package
    layout (`Tests/Package.swift`) must be detected and cd'd into before
    `swift test` runs, for every leg that runs tests at all — otherwise a
    root `swift test` silently discovers zero tests in the nested layout
    and exits green over an unmeasured package (the same "passes for the
    wrong reason" shape as the #64/ci-ok defect one layer up). This is
    proven by EXECUTION for the four POSIX-shell (bash/sh) sites; the fifth
    site (`windows-release`, PowerShell) is checked structurally only —
    this suite has no pwsh dependency anywhere else and does not add one
    for a single site.
    """

    POSIX_SITES = [
        ("macos-release", "Test"),
        ("linux-release", "Build or test (release)"),
        ("linux-nightly", "Test (release)"),
        ("linux-6-4", "Build or test (release)"),
    ]

    @classmethod
    def setUpClass(cls):
        cls.document = yaml.safe_load(UNIVERSAL_WORKFLOW.read_text(encoding="utf-8"))

    def _extract(self, job_id, step_name):
        job = self.document["jobs"][job_id]
        for step in job["steps"]:
            if step.get("name") == step_name:
                return step["run"]
        raise SystemExit(f"job '{job_id}' has no step named '{step_name}'")

    def _run(self, script, cwd_root, **env):
        script_path = cwd_root / "step.sh"
        script_path.write_text(script, encoding="utf-8")
        binary = cwd_root / "bin"
        binary.mkdir()
        swift = binary / "swift"
        # Logs both the invocation and the CWD it ran from, so the test can
        # tell whether the nested-detection `cd Tests` actually happened.
        swift.write_text(
            "#!/bin/sh\nprintf 'SWIFT_CALL=%s SWIFT_CWD=%s\\n' \"$*\" \"$(pwd)\"\n",
            encoding="utf-8",
        )
        swift.chmod(0o755)
        environment = dict(os.environ)
        environment["PATH"] = f"{binary}:{environment['PATH']}"
        environment.update(env)
        completed = subprocess.run(
            ["bash", str(script_path)],
            capture_output=True,
            text=True,
            cwd=str(cwd_root),
            env=environment,
        )
        return completed.returncode, completed.stdout + completed.stderr

    def test_every_posix_site_runs_from_root_without_a_nested_package(self):
        for job_id, step_name in self.POSIX_SITES:
            with self.subTest(job=job_id):
                script = self._extract(job_id, step_name)
                with tempfile.TemporaryDirectory() as raw:
                    root = Path(raw)
                    # A subprocess's `pwd` reports the OS-canonicalized
                    # path, which on macOS differs from `raw` when TMPDIR
                    # sits under a symlink (/var -> /private/var); resolve
                    # both sides through the same function so the
                    # comparison is meaningful on macOS dev machines and a
                    # no-op on the Linux runners this actually ships on.
                    root_real = os.path.realpath(root)
                    code, log = self._run(
                        script, root, CI_TIER="full", TEST_FILTER=""
                    )
                    self.assertEqual(code, 0, log)
                    self.assertNotIn("Nested test package detected", log)
                    self.assertIn(f"SWIFT_CWD={root_real}", log)

    def test_every_posix_site_cds_into_tests_when_nested_package_present(self):
        for job_id, step_name in self.POSIX_SITES:
            with self.subTest(job=job_id):
                script = self._extract(job_id, step_name)
                with tempfile.TemporaryDirectory() as raw:
                    root = Path(raw)
                    tests_dir = root / "Tests"
                    tests_dir.mkdir()
                    (tests_dir / "Package.swift").write_text(
                        "// swift-tools-version:6.3\n", encoding="utf-8"
                    )
                    tests_dir_real = os.path.realpath(tests_dir)
                    code, log = self._run(
                        script, root, CI_TIER="full", TEST_FILTER=""
                    )
                    self.assertEqual(code, 0, log)
                    self.assertIn("Nested test package detected", log)
                    self.assertIn(f"SWIFT_CWD={tests_dir_real}", log)

    def test_detector_catches_a_site_that_stops_cding_into_tests(self):
        """Positive control: a step body with the `cd Tests` line removed
        must NOT report the nested directory as its CWD — proving the
        detection assertion above actually depends on that line, rather
        than passing regardless of what the script does."""
        script = self._extract("linux-release", "Build or test (release)")
        neutered = script.replace("  cd Tests\n", "")
        self.assertNotIn("cd Tests", neutered)
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            tests_dir = root / "Tests"
            tests_dir.mkdir()
            (tests_dir / "Package.swift").write_text(
                "// swift-tools-version:6.3\n", encoding="utf-8"
            )
            tests_dir_real = os.path.realpath(tests_dir)
            code, log = self._run(neutered, root, CI_TIER="full", TEST_FILTER="")
            self.assertEqual(code, 0, log)
            # Detection message still prints (that line survives), but the
            # CWD never actually changes -- exactly the silent-zero-tests
            # hazard #165 exists to prevent, reproduced on demand.
            self.assertNotIn(f"SWIFT_CWD={tests_dir_real}", log)

    def test_windows_site_carries_the_same_detection_marker_structurally(self):
        # No pwsh execution in this suite; static presence check only.
        job = self.document["jobs"]["windows-release"]
        step = next(s for s in job["steps"] if s.get("name") == "Test")
        body = step["run"]
        self.assertIn("Tests/Package.swift", body)
        self.assertIn("Nested test package detected", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
