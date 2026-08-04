#!/usr/bin/env python3
"""Unit controls for validate-integrated-docs-compat.py (Task 4-01,
swift-institute/.github#276, #284).

Covers the two surfaces the real ~550-repository caller population and this
repository's own live files cannot both exercise in one place:

  - marker/input consistency (MARKER-MISSING / MARKER-ORPHANED), proven on
    synthetic fixtures rather than only "the real files currently pass",
    per the standing fixture rule that a check indistinguishable from the
    hazard being unreachable proves nothing;
  - `references_legacy_docs_wrapper()`, the predicate Task 5-03 transports
    to the live fleet — proven here to actually distinguish a legacy
    two-job caller from a migrated one-job caller, since no such
    population is reachable from this repository's own checkout.
"""
from __future__ import annotations

from contextlib import redirect_stdout
import importlib.util
from io import StringIO
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).parents[1] / "validate-integrated-docs-compat.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("validate_integrated_docs_compat", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

TESTS_DIR = Path(__file__).parent
REPO_ROOT = TESTS_DIR.parent.parent.parent
UNIVERSAL_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "swift-ci.yml"
WRAPPERS_DIR = TESTS_DIR / "fixtures" / "wrappers"
WRAPPER_PATHS = {
    "primitives": WRAPPERS_DIR / "primitives.swift-ci.yml",
    "standards": WRAPPERS_DIR / "standards.swift-ci.yml",
    "foundations": WRAPPERS_DIR / "foundations.swift-ci.yml",
}


WITH_INPUT_AND_MARKER = """\
on:
  workflow_call:
    inputs:
      integrated-docs:
        type: boolean
        default: false
        description: "TEMPORARY [temp-integrated-docs-4-01] compatibility input."
jobs:
  matrix:
    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
"""

WITH_INPUT_NO_MARKER = """\
on:
  workflow_call:
    inputs:
      integrated-docs:
        type: boolean
        default: false
        description: "A compatibility input with no tracking marker."
jobs:
  matrix:
    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
"""

MARKER_WITH_NO_INPUT = """\
on:
  workflow_call:
    inputs: {}
# stale comment: [temp-integrated-docs-4-01] used to live here
jobs:
  matrix:
    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
"""

NEITHER = """\
on:
  workflow_call:
    inputs: {}
jobs:
  matrix:
    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
"""


class MarkerConsistencyTests(unittest.TestCase):
    def _run(self, text: str) -> list[str]:
        output = StringIO()
        with redirect_stdout(output):
            n = module.check_marker_consistency("fixture", text)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), n)
        return lines

    def test_input_and_marker_together_is_clean(self) -> None:
        self.assertEqual(self._run(WITH_INPUT_AND_MARKER), [])

    def test_neither_present_is_clean(self) -> None:
        """The ordinary case for every file this script does not touch:
        no input, no marker — not a finding."""
        self.assertEqual(self._run(NEITHER), [])

    def test_input_without_marker_fires_marker_missing(self) -> None:
        lines = self._run(WITH_INPUT_NO_MARKER)
        self.assertEqual(len(lines), 1, lines)
        self.assertIn("MARKER-MISSING", lines[0])

    def test_marker_without_input_fires_marker_orphaned(self) -> None:
        lines = self._run(MARKER_WITH_NO_INPUT)
        self.assertEqual(len(lines), 1, lines)
        self.assertIn("MARKER-ORPHANED", lines[0])


LEGACY_CALLER = """\
name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit

  docs:
    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
    secrets: inherit
"""

MIGRATED_CALLER = """\
name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    with:
      integrated-docs: true
    secrets: inherit
"""

CROSS_ORG_LEGACY_CALLER = """\
name: CI
on: [push]
jobs:
  ci:
    uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
    secrets:
      PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}

  docs:
    uses: swift-standards/.github/.github/workflows/swift-docs.yml@main
    secrets:
      PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}
"""

NO_DOCS_JOB_AT_ALL = """\
name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
"""

DOCS_JOB_NAME_BUT_DIFFERENT_TARGET = """\
name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit

  docs:
    uses: some-org/some-repo/.github/workflows/unrelated.yml@main
"""


class LegacyDocsWrapperReferenceTests(unittest.TestCase):
    """`references_legacy_docs_wrapper()` — the predicate Task 5-03 runs
    against the live fleet. Every branch proven here so the function
    handed off to that task is not untested at handoff."""

    def test_legacy_two_job_caller_is_true(self) -> None:
        self.assertTrue(module.references_legacy_docs_wrapper(LEGACY_CALLER))

    def test_migrated_one_job_caller_is_false(self) -> None:
        self.assertFalse(module.references_legacy_docs_wrapper(MIGRATED_CALLER))

    def test_cross_org_legacy_caller_is_true(self) -> None:
        """The predicate must key on the `docs:` job's `uses:` shape, not
        on the same-org/cross-org secrets form — a cross-org legacy caller
        (explicit-forward secrets, no `secrets: inherit`) is exactly as
        legacy as a same-org one."""
        self.assertTrue(module.references_legacy_docs_wrapper(CROSS_ORG_LEGACY_CALLER))

    def test_no_docs_job_at_all_is_false(self) -> None:
        self.assertFalse(module.references_legacy_docs_wrapper(NO_DOCS_JOB_AT_ALL))

    def test_docs_job_targeting_something_else_is_false(self) -> None:
        """Negative control: a `docs:` job id alone is not the hazard —
        only one whose `uses:` actually targets a `swift-docs.yml`
        wrapper is. Guards against a naive "job id == docs" shortcut that
        would misclassify an unrelated job someone happened to name
        `docs`."""
        self.assertFalse(
            module.references_legacy_docs_wrapper(DOCS_JOB_NAME_BUT_DIFFERENT_TARGET)
        )


class LiveMarkerConsistencyTests(unittest.TestCase):
    """The real thing, not just the synthetic controls above: the shipped
    universal workflow and all three vendored layer-wrapper snapshots are
    marker-consistent RIGHT NOW. A future edit that adds/removes the input
    at one site without its marker (or vice versa) fails this, not just
    the synthetic fixtures."""

    def test_universal_workflow_is_clean(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            n = module.check_marker_consistency(
                "universal", UNIVERSAL_WORKFLOW.read_text(encoding="utf-8")
            )
        self.assertEqual(n, 0, output.getvalue())

    def test_every_vendored_wrapper_is_clean(self) -> None:
        for layer, path in WRAPPER_PATHS.items():
            with self.subTest(layer=layer):
                output = StringIO()
                with redirect_stdout(output):
                    n = module.check_marker_consistency(layer, path.read_text(encoding="utf-8"))
                self.assertEqual(n, 0, output.getvalue())


if __name__ == "__main__":
    unittest.main()
