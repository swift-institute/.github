#!/usr/bin/env python3
"""
Tests for compute-referenced-workflows.py (Task 6-01 reclaim,
swift-institute/.github#276, predicate 20).

This is the coordinator's reclaim of a hard finding on #43: the empty-
`referenced_workflows` UNMEASURED behaviour existed in swift-ci.yml but was
never tested by any file in this directory. This suite exercises the exact
script the workflow's "Emit effective-runtime receipt" step calls (via
`compute-referenced-workflows.py`, not a reimplementation of its logic), so
a change to the shipped decision is exactly what makes this suite fail.

Both directions are covered, so the suite discriminates rather than always
passing:
  - empty `referenced_workflows` -> UNMEASURED with the exact reason string
    and empty entries (the behaviour #43 claimed was tested and was not).
  - non-empty `referenced_workflows` -> measured, entries passed through
    verbatim, reason null.
  - the run object's key entirely absent -> treated the same as empty
    (jq's `.referenced_workflows | length` on a missing/null key is 0).

Usage: python3 .github/scripts/tests/test-compute-referenced-workflows.py
"""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent

_spec = importlib.util.spec_from_file_location(
    "compute_referenced_workflows", SCRIPTS_DIR / "compute-referenced-workflows.py"
)
compute_referenced_workflows = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(compute_referenced_workflows)

compute = compute_referenced_workflows.compute


class EmptyReferencedWorkflowsTests(unittest.TestCase):
    """The predicate-20 hazard: an empty array silently reported as
    measured, or silently dropped from the schema, rather than UNMEASURED.
    """

    def test_empty_list_is_unmeasured_with_exact_reason(self):
        result = compute({"referenced_workflows": []})
        self.assertEqual(result["status"], "UNMEASURED")
        self.assertEqual(
            result["reason"], "run object reported zero referenced_workflows"
        )
        self.assertEqual(result["entries"], [])

    def test_missing_key_is_treated_as_empty(self):
        # jq's `.referenced_workflows | length` on a run object missing the
        # key entirely evaluates `null | length` == 0, the same path as an
        # explicit empty array. A run object that never carries the key at
        # all must not fall through to "measured" by accident.
        result = compute({})
        self.assertEqual(result["status"], "UNMEASURED")
        self.assertEqual(result["entries"], [])

    def test_unmeasured_never_carries_a_measured_looking_status(self):
        result = compute({"referenced_workflows": []})
        self.assertNotEqual(result["status"], "measured")


class NonEmptyReferencedWorkflowsTests(unittest.TestCase):
    """The discriminating negative case: a genuinely non-empty
    `referenced_workflows` must be reported as measured, verbatim — proving
    this suite does not pass unconditionally regardless of input.
    """

    def test_non_empty_list_is_measured_with_entries_passed_through(self):
        entries = [
            {
                "path": "swift-institute/.github/.github/workflows/swift-ci.yml@refs/heads/main",
                "sha": "1439b01f65095a4c83bdd6aba00e77a0396c8458",
                "ref": "refs/heads/main",
            }
        ]
        result = compute({"referenced_workflows": entries})
        self.assertEqual(result["status"], "measured")
        self.assertIsNone(result["reason"])
        self.assertEqual(result["entries"], entries)

    def test_measured_result_never_carries_the_unmeasured_reason(self):
        entries = [{"path": "x", "sha": "y", "ref": "z"}]
        result = compute({"referenced_workflows": entries})
        self.assertNotEqual(
            result.get("reason"), "run object reported zero referenced_workflows"
        )


def run() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite(
        [
            loader.loadTestsFromTestCase(EmptyReferencedWorkflowsTests),
            loader.loadTestsFromTestCase(NonEmptyReferencedWorkflowsTests),
        ]
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(run())
