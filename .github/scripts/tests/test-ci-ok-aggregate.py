#!/usr/bin/env python3
"""Positive controls for swift-ci.yml's tier classifier and ci-ok aggregator.

Both are shell scripts embedded in a workflow, which is exactly the shape that
went wrong: `ci-ok` spent eight days reporting success over runs that compiled
nothing, because `all(.result == "success" or .result == "skipped")` cannot
tell a plan-sanctioned skip from a leg that stopped running. Reasoning about
whether an aggregator would fire is not the same act as watching it fire
(swift-institute/Internal's VALIDATOR-DISCIPLINE.md §3), so this suite feeds it
the shapes it must reject and asserts the exit status AND the diagnostic.

The scripts are EXTRACTED FROM swift-ci.yml rather than copied here, so the
bytes under test are the bytes that ship. If either step is renamed or
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

    def run_script(self, **env):
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
                    "GITHUB_REF": "refs/heads/main",
                    "GITHUB_SHA": "0" * 40,
                }
            )
            environment.update({k: v for k, v in env.items()})
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

    def aggregate(self, gating, results, tier="build"):
        needs = {job: {"result": results.get(job, "skipped")} for job in GATING_JOBS}
        return self.run_script(
            NEEDS_JSON=json.dumps(needs),
            PLANNED_GATING=gating,
            PLANNED_TIER=tier,
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


class ClassifierTests(ShellHarness):
    script = extract("plan", CLASSIFY_STEP)

    def classify(self, **env):
        base = {
            "FORCED_TIER": "",
            "EVENT_NAME": "push",
            "HEAD_MSG": "chore: something",
            "PLATFORM_SUPPORT": "",
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

    def test_tag_ref_forces_full(self):
        code, log, outputs = self.classify(GITHUB_REF="refs/tags/1.0.0")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

    def test_workflow_dispatch_forces_full(self):
        code, log, outputs = self.classify(EVENT_NAME="workflow_dispatch")
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["tier"], "full")

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
