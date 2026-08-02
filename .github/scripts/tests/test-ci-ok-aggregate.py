#!/usr/bin/env python3
"""Positive controls for swift-ci.yml's embedded control-plane shell steps.

Both are shell scripts embedded in a workflow, which is exactly the shape that
went wrong: `ci-ok` spent eight days reporting success over runs that compiled
nothing, because `all(.result == "success" or .result == "skipped")` cannot
tell a plan-sanctioned skip from a leg that stopped running. Reasoning about
whether an aggregator would fire is not the same act as watching it fire
(swift-institute/Internal's VALIDATOR-DISCIPLINE.md §3), so this suite feeds it
the shapes it must reject and asserts the exit status AND the diagnostic.

The scripts are EXTRACTED FROM swift-ci.yml rather than copied here, so the
bytes under test are the bytes that ship. If an extracted step is renamed or
removed, extraction fails loudly rather than the suite quietly testing
nothing — the empty-corpus rule from the same file.

Usage: python3 .github/scripts/tests/test-ci-ok-aggregate.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml

WORKFLOW = Path(__file__).parents[2] / "workflows" / "swift-ci.yml"

CLASSIFY_STEP = "Classify tier"
AGGREGATE_STEP = "Aggregate required-job results"

GATING_JOBS = [
    "plan",
    "macos-release",
    "linux-release",
    "windows-release",
    "format",
    "lint",
    "swift-linter",
]


def extract(job_id, step_name):
    """Return the `run:` body of a named step, or fail the suite saying so."""
    document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = document.get("jobs", {}).get(job_id)
    if job is None:
        raise SystemExit(f"{WORKFLOW}: no job '{job_id}' — extraction target gone")
    for step in job.get("steps", []):
        if step.get("name") == step_name:
            body = step.get("run")
            if not body:
                raise SystemExit(
                    f"{WORKFLOW}: step '{step_name}' in job '{job_id}' has no run: body"
                )
            return body
    raise SystemExit(
        f"{WORKFLOW}: job '{job_id}' has no step named '{step_name}'. "
        "This suite tests the shipped bytes by name; rename it here too."
    )


class ShellHarness(unittest.TestCase):
    """Run an extracted step body with a synthetic Actions environment."""

    script = ""

    def run_script(self, setup=None, **env):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            script = root / "step.sh"
            script.write_text(self.script, encoding="utf-8")
            output = root / "github_output"
            summary = root / "github_summary"
            output.touch()
            summary.touch()
            environment = dict(os.environ)
            environment.update(
                {
                    "GITHUB_OUTPUT": str(output),
                    "GITHUB_STEP_SUMMARY": str(summary),
                    "GITHUB_REF": "refs/heads/feature",
                    "GITHUB_SHA": "0" * 40,
                    "INPUT_TARGET_REPOSITORY": "",
                    "INPUT_REF": "",
                    "PULL_REQUEST_HEAD_REPOSITORY": "",
                    "PULL_REQUEST_HEAD_SHA": "",
                    "TRIGGER_REPOSITORY": "swift-institute/example",
                    "TRIGGER_SHA": "0" * 40,
                }
            )
            environment.update({k: v for k, v in env.items()})
            if setup is not None:
                setup(root, environment)
            completed = subprocess.run(
                ["bash", str(script)],
                capture_output=True,
                text=True,
                cwd=str(root),
                env=environment,
            )
            outputs = {}
            for line in output.read_text(encoding="utf-8").splitlines():
                if "=" in line:
                    key, _, value = line.partition("=")
                    outputs[key] = value
            self.summary = summary.read_text(encoding="utf-8")
            return (
                completed.returncode,
                completed.stdout + completed.stderr,
                outputs,
            )


class AggregatorTests(ShellHarness):
    script = extract("ci-ok", AGGREGATE_STEP)

    def aggregate(
        self,
        gating,
        results,
        tier="build",
        planned_repository="swift-institute/example",
        planned_sha="a" * 40,
        expected_repository="swift-institute/example",
        expected_sha="a" * 40,
        require_full_tier="false",
    ):
        needs = {job: {"result": results.get(job, "skipped")} for job in GATING_JOBS}
        return self.run_script(
            NEEDS_JSON=json.dumps(needs),
            PLANNED_GATING=gating,
            PLANNED_TIER=tier,
            PLANNED_SUBJECT_REPOSITORY=planned_repository,
            PLANNED_SUBJECT_SHA=planned_sha,
            EXPECTED_SUBJECT_REPOSITORY=expected_repository,
            EXPECTED_SUBJECT_SHA=expected_sha,
            REQUIRE_FULL_TIER=require_full_tier,
        )

    # ---- the shapes that must pass -------------------------------------

    def test_build_tier_that_actually_built_passes(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "success",
            },
        )
        self.assertEqual(code, 0, log)
        # A green that does not say what it verified is the shape this
        # replaced, so the summary is asserted rather than merely produced:
        # every figure in it has to come from the results just inspected.
        self.assertIn("built on `linux-release`", self.summary)
        self.assertIn("| `linux-release` | success | success |", self.summary)
        self.assertIn("| `macos-release` | skipped | skipped |", self.summary)
        self.assertIn("tier `build`", self.summary)

    def test_failure_summary_names_the_offending_leg(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "skipped",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("ci-ok: FAIL", self.summary)
        self.assertIn("built on `nothing`", self.summary)
        self.assertIn("| `linux-release` | success | skipped |", self.summary)

    def test_full_tier_passes(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release,macos-release,windows-release",
            {job: "success" for job in GATING_JOBS},
            tier="full",
        )
        self.assertEqual(code, 0, log)

    def test_platform_support_excluded_legs_may_skip(self):
        # A Linux-only package: macos/windows are absent from the gating set,
        # so their skips are sanctioned and must not fail the run.
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "success",
                "macos-release": "skipped",
                "windows-release": "skipped",
            },
        )
        self.assertEqual(code, 0, log)

    # ---- the shapes that must fail -------------------------------------

    def test_selected_build_leg_that_skipped_fails(self):
        """The defect. Before 2026-07-28 this exact shape reported success."""
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "skipped",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("linux-release", log)
        self.assertIn("selected by the plan", log)

    def test_build_free_gating_set_fails(self):
        """The retired lint tier's shape: three quality legs, nothing built."""
        code, log, _ = self.aggregate(
            "format,lint,swift-linter",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("compiled nothing", log)

    def test_unplanned_execution_fails(self):
        # A leg ran that the plan did not select: the guards and the plan have
        # drifted, and the green would be over an unknown shape.
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "success",
                "macos-release": "success",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("without the plan selecting it", log)

    def test_failed_gating_leg_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "failure",
                "linux-release": "success",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("swift-linter", log)

    def test_failed_plan_fails(self):
        code, log, _ = self.aggregate("", {"plan": "failure"})
        self.assertNotEqual(code, 0, log)
        self.assertIn("no verification tier was established", log)

    def test_empty_gating_set_fails(self):
        code, log, _ = self.aggregate("", {"plan": "success"})
        self.assertNotEqual(code, 0, log)
        self.assertIn("named no gating legs", log)

    def test_empty_subject_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {job: "success" for job in GATING_JOBS},
            planned_sha="",
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("empty CI subject", log)

    def test_stale_or_mismatched_subject_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {job: "success" for job in GATING_JOBS},
            planned_sha="a" * 40,
            expected_sha="b" * 40,
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("Stale or mismatched evidence", log)

    def test_main_non_full_tier_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "success",
            },
            tier="build",
            require_full_tier="true",
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("requires the full tier", log)

    def test_only_main_requires_full_tier_at_aggregation(self):
        document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        step = next(
            step
            for step in document["jobs"]["ci-ok"]["steps"]
            if step.get("name") == AGGREGATE_STEP
        )
        self.assertEqual(
            step["env"]["REQUIRE_FULL_TIER"],
            "${{ github.ref == 'refs/heads/main' }}",
        )

    def test_selected_full_leg_that_skipped_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release,macos-release,windows-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "success",
                "macos-release": "success",
                "windows-release": "skipped",
            },
            tier="full",
            require_full_tier="true",
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("windows-release", log)
        self.assertIn("selected by the plan", log)

    def test_cancelled_gating_leg_fails(self):
        code, log, _ = self.aggregate(
            "format,lint,swift-linter,linux-release",
            {
                "plan": "success",
                "format": "success",
                "lint": "success",
                "swift-linter": "success",
                "linux-release": "cancelled",
            },
        )
        self.assertNotEqual(code, 0, log)


class ConfiguredLinterAdjudicationTests(ShellHarness):
    """The configured-rule path must not report a clean run over no measure."""

    script = extract("swift-linter", "Run swift-linter (consumer Lint.swift)")

    def run_linter(self, output, exit_code=0):
        def configure(root, environment):
            bash_env = root / "mock-swift-linter.bash"
            bash_env.write_text(
                """swift-linter() {
  if [ "$2" != "--exit-policy" ] || [ "$3" != "strict" ]; then
    echo "unexpected swift-linter arguments: $*"
    return 97
  fi
  printf '%s\\n' "$LINTER_OUTPUT"
  return "$LINTER_EXIT"
}
""",
                encoding="utf-8",
            )
            environment["BASH_ENV"] = str(bash_env)
            environment["GITHUB_WORKSPACE"] = str(root)

        return self.run_script(
            setup=configure,
            LINTER_OUTPUT=output,
            LINTER_EXIT=str(exit_code),
        )

    def test_real_configured_run_passes(self):
        code, log, _ = self.run_linter("93 active rules · 4 files linted · 0 violations")
        self.assertEqual(code, 0, log)
        self.assertIn("swift-linter (Lint.swift)", self.summary)

    def test_missing_summary_fails(self):
        code, log, _ = self.run_linter("no summary was emitted")
        self.assertNotEqual(code, 0, log)
        self.assertIn("emitted no run summary", log)

    def test_zero_active_rules_fails(self):
        code, log, _ = self.run_linter("0 active rules · 4 files linted · 0 violations")
        self.assertNotEqual(code, 0, log)
        self.assertIn("loaded 0 rules from Lint.swift", log)

    def test_zero_linted_files_fails(self):
        code, log, _ = self.run_linter("93 active rules · 0 files linted · 0 violations")
        self.assertNotEqual(code, 0, log)
        self.assertIn("linted 0 files", log)

    def test_existing_strict_failure_is_preserved(self):
        code, log, _ = self.run_linter(
            "93 active rules · 4 files linted · 1 violation", exit_code=42
        )
        self.assertEqual(code, 42, log)


@unittest.skip("The published-binary installation path no longer has a rule-pack resolution step.")
class RunnerDigestTests(ShellHarness):
    """Every baked standard bundle revision must affect the fallback key."""

    script = ""

    def resolve(self, standards_rules_sha):
        def configure(root, environment):
            bash_env = root / "mock-git.bash"
            bash_env.write_text(
                """git() {
  if [ "$1" != "ls-remote" ]; then
    command git "$@"
    return
  fi
  case "$2" in
    *swift-primitives-linter-rules.git) SHA=1111111111111111111111111111111111111111 ;;
    *swift-institute-linter-rules.git) SHA=2222222222222222222222222222222222222222 ;;
    *swift-standards-linter-rules.git) SHA="$STANDARDS_RULES_SHA" ;;
    *swift-linter-rules.git) SHA=3333333333333333333333333333333333333333 ;;
    *swift-linter-primitives.git) SHA=4444444444444444444444444444444444444444 ;;
    *) echo "unexpected ls-remote source: $2" >&2; return 98 ;;
  esac
  printf '%s\\trefs/heads/main\\n' "$SHA"
}
""",
                encoding="utf-8",
            )
            environment["BASH_ENV"] = str(bash_env)

        return self.run_script(
            setup=configure,
            STANDARDS_RULES_SHA=standards_rules_sha,
        )

    def test_standards_bundle_revision_changes_fallback_digest(self):
        code, first_log, first = self.resolve("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        self.assertEqual(code, 0, first_log)
        code, second_log, second = self.resolve("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        self.assertEqual(code, 0, second_log)
        self.assertNotEqual(first["digest"], second["digest"])
        self.assertIn("standrules=", second_log)


class ClassifierTests(ShellHarness):
    script = extract("plan", CLASSIFY_STEP)

    def classify(self, **env):
        base = {
            "FORCED_TIER": "",
            "EVENT_NAME": "push",
            "HEAD_MSG": "chore: something",
            "PLATFORM_SUPPORT": "",
            "INPUT_TARGET_REPOSITORY": "",
            "INPUT_REF": "",
            "PULL_REQUEST_HEAD_REPOSITORY": "",
            "PULL_REQUEST_HEAD_SHA": "",
            "TRIGGER_REPOSITORY": "swift-institute/example",
            "TRIGGER_SHA": "a" * 40,
        }
        base.update(env)
        return self.run_script(**base)

    def test_ordinary_push_gets_build_with_a_build_leg(self):
        code, log, outputs = self.classify()
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "build")
        self.assertIn("linux-release", outputs["legs"].split(","))
        self.assertIn("linux-release", outputs["gating"].split(","))

    def test_docs_only_push_no_longer_downgrades(self):
        """The auto-downgrade is gone: nothing routes a push away from build."""
        code, log, outputs = self.classify(HEAD_MSG="docs: fix a typo [ci lint]")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "build")
        self.assertIn("linux-release", outputs["gating"].split(","))

    def test_forced_lint_tier_is_rejected(self):
        code, log, _ = self.classify(FORCED_TIER="lint")
        self.assertNotEqual(code, 0, log)
        self.assertIn("retired", log)

    def test_commit_token_forces_full(self):
        code, log, outputs = self.classify(HEAD_MSG="feat: big change [ci full]")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

    def test_explicit_full_request_stays_full(self):
        code, log, outputs = self.classify(FORCED_TIER="full")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

    def test_tag_ref_forces_full(self):
        code, log, outputs = self.classify(GITHUB_REF="refs/tags/1.0.0")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

    def test_workflow_dispatch_forces_full(self):
        code, log, outputs = self.classify(EVENT_NAME="workflow_dispatch")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

    def test_pull_request_defaults_to_build_and_uses_exact_head_subject(self):
        code, log, outputs = self.classify(
            EVENT_NAME="pull_request",
            PULL_REQUEST_HEAD_REPOSITORY="fork/example",
            PULL_REQUEST_HEAD_SHA="b" * 40,
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "build")
        self.assertEqual(outputs["subject-repository"], "fork/example")
        self.assertEqual(outputs["subject-sha"], "b" * 40)

    def test_main_push_defaults_to_full_and_uses_exact_trigger_sha(self):
        code, log, outputs = self.classify(
            GITHUB_REF="refs/heads/main", TRIGGER_SHA="c" * 40
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")
        self.assertEqual(outputs["subject-repository"], "swift-institute/example")
        self.assertEqual(outputs["subject-sha"], "c" * 40)

    def test_explicit_build_cannot_weaken_main_integration(self):
        code, log, outputs = self.classify(
            GITHUB_REF="refs/heads/main", FORCED_TIER="build", TRIGGER_SHA="c" * 40
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")
        self.assertEqual(outputs["subject-repository"], "swift-institute/example")
        self.assertEqual(outputs["subject-sha"], "c" * 40)

    def test_build_tier_keeps_quality_gates_and_a_release_build(self):
        code, log, outputs = self.classify(FORCED_TIER="build")
        self.assertEqual(code, 0, log)
        gating = set(outputs["gating"].split(","))
        self.assertTrue({"format", "lint", "swift-linter"} <= gating)
        self.assertTrue(
            {"macos-release", "linux-release", "windows-release"} & gating
        )

    def test_platform_support_filters_legs_not_only_guards(self):
        code, log, outputs = self.classify(FORCED_TIER="full", PLATFORM_SUPPORT="linux")
        self.assertEqual(code, 0, log)
        legs = outputs["legs"].split(",")
        self.assertIn("linux-release", legs)
        self.assertNotIn("macos-release", legs)
        self.assertNotIn("windows-release", legs)
        self.assertNotIn("apple-simulator-build", legs)
        self.assertEqual(
            outputs["gating"].split(","),
            ["format", "lint", "swift-linter", "linux-release"],
        )

    def test_apple_only_package_builds_on_macos(self):
        code, log, outputs = self.classify(PLATFORM_SUPPORT="apple")
        self.assertEqual(code, 0, log)
        self.assertIn("macos-release", outputs["gating"].split(","))

    def test_gating_set_always_contains_a_build_leg(self):
        builds = {"macos-release", "linux-release", "windows-release"}
        for tier in ("", "build", "full"):
            for platforms in ("", "apple", "linux", "windows", "apple,linux"):
                with self.subTest(tier=tier, platforms=platforms):
                    code, log, outputs = self.classify(
                        FORCED_TIER=tier, PLATFORM_SUPPORT=platforms
                    )
                    self.assertEqual(code, 0, log)
                    self.assertTrue(
                        builds & set(outputs["gating"].split(",")),
                        f"no build leg in gating set {outputs['gating']!r}",
                    )

    def test_unknown_platform_family_fails(self):
        code, log, _ = self.classify(PLATFORM_SUPPORT="solaris")
        self.assertNotEqual(code, 0, log)
        self.assertIn("invalid platform-support family", log)


class AdvisoryPostureTests(unittest.TestCase):
    """linux-6-4 runs on every push and gates nothing. Both halves matter.

    Settled ruling 2026-07-28, after the posture was flipped to gating and
    withdrawn the same evening. The two halves fail in opposite directions and
    neither is visible in the other's diff, so both are asserted here: drop it
    from the build tier and 6.4 evidence silently reverts to weekly; add it to
    the gating set and 62 repositories go red on their next push.
    """

    document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    classifier = extract("plan", CLASSIFY_STEP)

    def test_it_runs_on_every_ordinary_push(self):
        harness = ShellHarness()
        harness.script = self.classifier
        code, log, outputs = harness.run_script(
            FORCED_TIER="",
            EVENT_NAME="push",
            HEAD_MSG="chore: something",
            PLATFORM_SUPPORT="",
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "build")
        self.assertIn("linux-6-4", outputs["legs"].split(","))

    def test_it_does_not_gate(self):
        harness = ShellHarness()
        harness.script = self.classifier
        for platforms in ("", "linux", "apple,linux"):
            with self.subTest(platforms=platforms):
                _, _, outputs = harness.run_script(
                    FORCED_TIER="",
                    EVENT_NAME="push",
                    HEAD_MSG="chore",
                    PLATFORM_SUPPORT=platforms,
                )
                self.assertNotIn("linux-6-4", outputs["gating"].split(","))

    def test_the_job_stays_tolerant_and_out_of_ci_ok(self):
        # Three structural sites, none of them reachable from the extracted
        # script, all of which must agree for "advisory" to be true.
        self.assertIs(
            self.document["jobs"]["linux-6-4"].get("continue-on-error"), True
        )
        self.assertNotIn("linux-6-4", self.document["jobs"]["ci-ok"]["needs"])
        self.assertIn(
            "linux-6-4", self.document["jobs"]["advisory-summary"]["needs"]
        )

    def test_an_apple_only_package_does_not_run_a_linux_nightly(self):
        harness = ShellHarness()
        harness.script = self.classifier
        _, _, outputs = harness.run_script(
            FORCED_TIER="",
            EVENT_NAME="push",
            HEAD_MSG="chore",
            PLATFORM_SUPPORT="apple",
        )
        self.assertNotIn("linux-6-4", outputs["legs"].split(","))


if __name__ == "__main__":
    unittest.main(verbosity=2)
