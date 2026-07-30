#!/usr/bin/env python3
"""Fail-closed controls for check-lint-validators-weekly-parity.py (#117).

Two things must be true of the drift checker:

  1. It reports zero drift against the actual shipped
     lint-validators-weekly.yml — the integration assertion that the real
     file stays wired.
  2. It CAN fail: a synthetic, minimal-but-representative workflow with
     one scan-* leg removed from exactly one of the five report surfaces
     must produce a finding naming that job and that surface. Without
     this positive control, a checker that silently no-ops would report
     the same "zero findings" as a fully-wired file — the exact failure
     mode #79 exists to catch.

The synthetic fixture is a 2-leg workflow (scan-alpha fully wired,
scan-beta the one under test) built fresh per test case so each test
mutates exactly one surface and leaves the other four correct — proving
the checker attributes the gap to the right surface, not just "something
is wrong somewhere".
"""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

import yaml

# The checker script's filename has hyphens (matches this repo's
# check-*.py / validate-*.py convention), so it cannot be imported with a
# plain `import` statement — load it from its file path instead.
_SCRIPT = Path(__file__).parents[1] / "check-lint-validators-weekly-parity.py"
_spec = importlib.util.spec_from_file_location("check_lint_validators_weekly_parity", _SCRIPT)
assert _spec is not None and _spec.loader is not None
_checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_checker)
check_workflow_dict = _checker.check_workflow_dict
get_scan_jobs = _checker.get_scan_jobs

REAL_WORKFLOW = Path(__file__).parents[2] / "workflows" / "lint-validators-weekly.yml"

# A minimal but structurally faithful stand-in for the report job's shape:
# two scan-* jobs (alpha, beta), both fully wired across all five surfaces.
# Individual tests mutate exactly one surface for exactly one job.
BASE = """
jobs:
  scan-alpha:
    uses: ./.github/workflows/validate-alpha.yml
  scan-beta:
    uses: ./.github/workflows/validate-beta.yml
  report:
    needs:
      - scan-alpha
      - scan-beta
    if: always() && (needs.scan-alpha.result != 'skipped' || needs.scan-beta.result != 'skipped')
    steps:
      - name: Build issue body
        env:
          RESULT_ALPHA: ${{ needs.scan-alpha.result }}
          RESULT_BETA: ${{ needs.scan-beta.result }}
        run: |
          for pair in "alpha:$RESULT_ALPHA" "beta:$RESULT_BETA"; do
            echo "$pair"
          done
          cat > body.md <<EOF
          ### validate-alpha
          Job status: `${RESULT_ALPHA}`.

          ### validate-beta
          Job status: `${RESULT_BETA}`.
          EOF
"""


def load(text: str) -> dict:
    return yaml.safe_load(text)


class RealWorkflowTests(unittest.TestCase):
    def test_real_workflow_has_no_drift(self) -> None:
        data = load(REAL_WORKFLOW.read_text(encoding="utf-8"))
        findings = check_workflow_dict(data)
        self.assertEqual(findings, [], f"drift found in the real workflow: {findings}")

    def test_real_workflow_scan_jobs_nonempty(self) -> None:
        # A sanity floor: if this ever returns zero, the discovery logic
        # itself is broken (matching #117's own "count from the wrong
        # root is not evidence" caution), and the "no drift" result above
        # would be vacuous.
        data = load(REAL_WORKFLOW.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(get_scan_jobs(data)), 10)


class SyntheticFixtureIsClean(unittest.TestCase):
    def test_base_fixture_has_no_drift(self) -> None:
        # The fixture itself must be a valid pass case before any test
        # relies on mutating exactly one surface away from it.
        findings = check_workflow_dict(load(BASE))
        self.assertEqual(findings, [])


class LegRemovedPositiveControls(unittest.TestCase):
    """Each test removes scan-beta from exactly one surface and asserts
    the checker flags scan-beta on that surface — and only that job."""

    def test_missing_from_needs_list_is_caught(self) -> None:
        data = load(BASE)
        data["jobs"]["report"]["needs"] = ["scan-alpha"]
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "needs"}
        self.assertIn("scan-beta", jobs_flagged)
        self.assertNotIn("scan-alpha", jobs_flagged)

    def test_missing_from_if_condition_is_caught(self) -> None:
        data = load(BASE)
        data["jobs"]["report"]["if"] = "always() && (needs.scan-alpha.result != 'skipped')"
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "if-condition"}
        self.assertIn("scan-beta", jobs_flagged)
        self.assertNotIn("scan-alpha", jobs_flagged)

    def test_missing_from_result_env_is_caught(self) -> None:
        data = load(BASE)
        step = data["jobs"]["report"]["steps"][0]
        del step["env"]["RESULT_BETA"]
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "result-env"}
        self.assertIn("scan-beta", jobs_flagged)
        self.assertNotIn("scan-alpha", jobs_flagged)

    def test_result_env_pointing_at_wrong_job_is_caught(self) -> None:
        # Not just absent — wired to the wrong needs.<job>.result is the
        # same defect class (a copy-paste that didn't get repointed).
        data = load(BASE)
        step = data["jobs"]["report"]["steps"][0]
        step["env"]["RESULT_BETA"] = "${{ needs.scan-alpha.result }}"
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "result-env"}
        self.assertIn("scan-beta", jobs_flagged)

    def test_missing_from_aggregation_pair_list_is_caught(self) -> None:
        data = load(BASE)
        step = data["jobs"]["report"]["steps"][0]
        step["run"] = step["run"].replace(' "beta:$RESULT_BETA"', "")
        self.assertNotIn('"beta:$RESULT_BETA"', step["run"])  # mutation actually landed
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "aggregation-pair-list"}
        self.assertIn("scan-beta", jobs_flagged)
        self.assertNotIn("scan-alpha", jobs_flagged)

    def test_missing_issue_body_section_is_caught(self) -> None:
        data = load(BASE)
        step = data["jobs"]["report"]["steps"][0]
        # YAML's `|` block scalar strips the common leading indentation, so
        # the parsed run: string carries no leading spaces on these lines
        # (unlike the indented literal in BASE above).
        marker = "\n\n### validate-beta\nJob status: `${RESULT_BETA}`.\n"
        self.assertIn(marker, step["run"])  # fixture assumption, made explicit
        step["run"] = step["run"].replace(marker, "\n")
        findings = check_workflow_dict(data)
        jobs_flagged = {job for job, surface, _ in findings if surface == "issue-body-section"}
        self.assertIn("scan-beta", jobs_flagged)
        self.assertNotIn("scan-alpha", jobs_flagged)

    def test_a_thirteenth_leg_added_with_zero_wiring_is_caught_on_all_five_surfaces(self) -> None:
        # The exact scenario named in #117's Observable result: a future
        # scan leg added without any report wiring must turn this check
        # red, not just partially yellow.
        data = load(BASE)
        data["jobs"]["scan-gamma"] = {"uses": "./.github/workflows/validate-gamma.yml"}
        findings = check_workflow_dict(data)
        surfaces_flagged = {surface for job, surface, _ in findings if job == "scan-gamma"}
        self.assertEqual(
            surfaces_flagged,
            {"needs", "if-condition", "result-env", "aggregation-pair-list", "issue-body-section"},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
