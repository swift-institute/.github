#!/usr/bin/env python3
"""Fail-closed controls for check-scheduled-workflow-alert-parity.py (#123).

Two things must be true of the drift checker:

  1. It reports zero drift against the actual shipped workflow directory
     and alert-scheduled-workflow-failure.yml — the integration assertion
     that the real watch list stays wired to the real schedule: triggers.
  2. It CAN fail: a synthetic, minimal-but-representative pair (a
     scheduled-workflow set plus a watch list) with one leg removed, or
     one stale leg added, must produce a finding naming that workflow and
     that surface. Without this positive control, a checker that silently
     no-ops would report the same "zero findings" as a fully-wired watch
     list — the same failure mode #117 and #79 exist to catch, applied
     here to #123's own watch list.

The synthetic fixtures operate on the checker's pure dict/set functions
directly (scheduled_names_from_docs / watched_names_from_alert_doc /
compute_drift) rather than real files on disk, mirroring
test-lint-validators-weekly-drift.py's approach for #117's checker.
"""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

import yaml

# The checker script's filename has hyphens (matches this repo's
# check-*.py / validate-*.py convention), so it cannot be imported with a
# plain `import` statement — load it from its file path instead.
_SCRIPT = Path(__file__).parents[1] / "check-scheduled-workflow-alert-parity.py"
_spec = importlib.util.spec_from_file_location("check_scheduled_workflow_alert_parity", _SCRIPT)
assert _spec is not None and _spec.loader is not None
_checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_checker)
scheduled_names_from_docs = _checker.scheduled_names_from_docs
watched_names_from_alert_doc = _checker.watched_names_from_alert_doc
compute_drift = _checker.compute_drift
load_docs = _checker.load_docs

WORKFLOWS_DIR = Path(__file__).parents[2] / "workflows"
ALERT_WORKFLOW = WORKFLOWS_DIR / "alert-scheduled-workflow-failure.yml"

# A minimal but structurally faithful stand-in for two scheduled workflows
# (alpha, beta), both fully wired into a watch list. Individual tests
# mutate exactly one surface for exactly one workflow.
SCHEDULED_DOCS = {
    "scan-alpha.yml": {"name": "scan-alpha", "on": {"schedule": [{"cron": "0 5 * * *"}]}},
    "scan-beta.yml": {"name": "scan-beta", "on": {"schedule": [{"cron": "0 6 * * *"}]}},
    # A non-scheduled workflow in the same directory must not appear in
    # the scheduled set at all (sanity floor for the discovery predicate).
    "push-only.yml": {"name": "push-only", "on": {"push": {"branches": ["main"]}}},
}


def alert_doc(workflows: list[str]) -> dict:
    return {"on": {"workflow_run": {"types": ["completed"], "workflows": workflows}}}


class RealWorkflowTests(unittest.TestCase):
    def test_real_watch_list_has_no_drift(self) -> None:
        alert_data = yaml.safe_load(ALERT_WORKFLOW.read_text(encoding="utf-8"))
        docs = load_docs(WORKFLOWS_DIR, yaml, exclude={ALERT_WORKFLOW.name})
        scheduled = scheduled_names_from_docs(docs)
        watched = watched_names_from_alert_doc(alert_data)
        findings = compute_drift(scheduled, watched)
        self.assertEqual(findings, [], f"drift found against the real watch list: {findings}")

    def test_real_scheduled_set_nonempty(self) -> None:
        # A sanity floor: if this ever returns zero, the discovery logic
        # itself is broken (matching #117's own "count from the wrong
        # root is not evidence" caution), and the "no drift" result above
        # would be vacuous.
        docs = load_docs(WORKFLOWS_DIR, yaml, exclude={ALERT_WORKFLOW.name})
        scheduled = scheduled_names_from_docs(docs)
        self.assertGreaterEqual(len(scheduled), 15)


class SyntheticFixtureIsClean(unittest.TestCase):
    def test_base_fixture_has_no_drift(self) -> None:
        scheduled = scheduled_names_from_docs(SCHEDULED_DOCS)
        watched = watched_names_from_alert_doc(alert_doc(["scan-alpha", "scan-beta"]))
        self.assertEqual(compute_drift(scheduled, watched), [])

    def test_push_only_workflow_is_not_scheduled(self) -> None:
        scheduled = scheduled_names_from_docs(SCHEDULED_DOCS)
        self.assertNotIn("push-only", scheduled)


class LegRemovedOrAddedPositiveControls(unittest.TestCase):
    """Each test perturbs exactly one surface away from the clean base and
    asserts the checker flags exactly the perturbed workflow — and only
    that one."""

    def test_missing_from_watch_list_is_caught(self) -> None:
        scheduled = scheduled_names_from_docs(SCHEDULED_DOCS)
        watched = watched_names_from_alert_doc(alert_doc(["scan-alpha"]))  # beta dropped
        findings = compute_drift(scheduled, watched)
        flagged = {name for name, surface, _ in findings if surface == "missing-from-watch-list"}
        self.assertIn("scan-beta", flagged)
        self.assertNotIn("scan-alpha", flagged)

    def test_stale_watch_entry_is_caught(self) -> None:
        scheduled = scheduled_names_from_docs(SCHEDULED_DOCS)
        # gamma is watched but no doc has a schedule: trigger with that name.
        watched = watched_names_from_alert_doc(alert_doc(["scan-alpha", "scan-beta", "scan-gamma"]))
        findings = compute_drift(scheduled, watched)
        flagged = {name for name, surface, _ in findings if surface == "stale-watch-entry"}
        self.assertIn("scan-gamma", flagged)
        self.assertNotIn("scan-alpha", flagged)
        self.assertNotIn("scan-beta", flagged)

    def test_a_third_scheduled_workflow_added_with_zero_wiring_is_caught(self) -> None:
        # The exact scenario #123 exists to close: a new schedule:-triggered
        # workflow lands with no corresponding watch-list entry at all.
        docs = dict(SCHEDULED_DOCS)
        docs["scan-delta.yml"] = {"name": "scan-delta", "on": {"schedule": [{"cron": "0 7 * * *"}]}}
        scheduled = scheduled_names_from_docs(docs)
        watched = watched_names_from_alert_doc(alert_doc(["scan-alpha", "scan-beta"]))
        findings = compute_drift(scheduled, watched)
        flagged = {(name, surface) for name, surface, _ in findings}
        self.assertIn(("scan-delta", "missing-from-watch-list"), flagged)

    def test_schedule_trigger_removed_from_a_watched_workflow_is_caught(self) -> None:
        # The symmetric case: a workflow that used to be scheduled loses its
        # schedule: trigger (e.g. converted to push-only) but the watch
        # list is not pruned — a stale entry, not a silent gap, but still
        # evidence the list stopped tracking reality.
        docs = dict(SCHEDULED_DOCS)
        docs["scan-beta.yml"] = {"name": "scan-beta", "on": {"push": {"branches": ["main"]}}}
        scheduled = scheduled_names_from_docs(docs)
        watched = watched_names_from_alert_doc(alert_doc(["scan-alpha", "scan-beta"]))
        findings = compute_drift(scheduled, watched)
        flagged = {(name, surface) for name, surface, _ in findings}
        self.assertIn(("scan-beta", "stale-watch-entry"), flagged)


if __name__ == "__main__":
    unittest.main(verbosity=2)
