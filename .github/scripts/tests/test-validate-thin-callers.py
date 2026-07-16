#!/usr/bin/env python3

from __future__ import annotations

from contextlib import redirect_stdout
import importlib.util
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "validate-thin-callers.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("validate_thin_callers", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DiagnosticFactoringTests(unittest.TestCase):
    def validate(self, workflow: str) -> list[str]:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / "Package.swift").write_text(
                "// swift-tools-version: 6.3\n", encoding="utf-8"
            )
            workflows = root / ".github" / "workflows"
            workflows.mkdir(parents=True)
            (workflows / "ci.yml").write_text(workflow, encoding="utf-8")
            output = StringIO()
            with redirect_stdout(output):
                module.main("swift-foundations/fixture", str(root))
        return [
            line
            for line in output.getvalue().splitlines()
            if "\tGH-REPO-074\t" in line
        ]

    def test_all_inline_root_factors_secondary_diagnostics(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  macos_tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift test
  ubuntu_tests:
    runs-on: ubuntu-20.04
    steps:
      - uses: actions/checkout@v4
      - run: swift test
"""
        self.assertTrue(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        lines = self.validate(workflow)
        self.assertEqual(len(lines), 1)
        self.assertIn("does not reference any reusable", lines[0])

    def test_mixed_workflow_retains_independent_inline_diagnostics(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  central:
    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
  local:
    runs-on: ubuntu-latest
    steps:
      - run: swift test
"""
        self.assertFalse(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        lines = self.validate(workflow)
        self.assertEqual(len(lines), 2)
        self.assertTrue(any("inline `runs-on:`" in line for line in lines))
        self.assertTrue(any("inline `steps:`" in line for line in lines))

    def test_partial_job_shape_fails_closed_with_all_diagnostics(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  build: &inline
    runs-on: ubuntu-latest
    steps:
      - run: swift test
"""
        self.assertFalse(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        lines = self.validate(workflow)
        self.assertEqual(len(lines), 3)

    def test_runs_on_only_job_retains_both_existing_diagnostics(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
"""
        self.assertFalse(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        lines = self.validate(workflow)
        self.assertEqual(len(lines), 2)
        self.assertTrue(any("inline `runs-on:`" in line for line in lines))
        self.assertTrue(any("does not reference any reusable" in line for line in lines))

    def test_steps_only_job_retains_both_existing_diagnostics(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  build:
    steps:
      - run: swift test
"""
        self.assertFalse(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        lines = self.validate(workflow)
        self.assertEqual(len(lines), 2)
        self.assertTrue(any("inline `steps:`" in line for line in lines))
        self.assertTrue(any("does not reference any reusable" in line for line in lines))

    def test_unparseable_canonical_indentation_fails_closed(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  build:
    runs-on: [ubuntu-latest
    steps:
      - run: swift test
"""
        self.assertTrue(module.has_complete_canonical_jobs_mapping(
            workflow, list(module.iter_jobs(workflow))
        ))
        self.assertFalse(
            module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
        )
        self.assertEqual(len(self.validate(workflow)), 3)

    def test_many_cofirings_never_create_precedence(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  central:
    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
  local:
    runs-on: ubuntu-latest
    steps:
      - run: swift test
"""
        for _ in range(1_000):
            self.assertFalse(
                module.gh_repo_074_no_reusable_root_supersedes_inline(workflow)
            )
        self.assertEqual(len(self.validate(workflow)), 2)

    def test_tool_reusable_carve_out_remains_exempt(self) -> None:
        workflow = """name: tool
on:
  workflow_call:
jobs:
  tool:
    runs-on: ubuntu-latest
    steps:
      - run: swift run tool
"""
        self.assertEqual(self.validate(workflow), [])


if __name__ == "__main__":
    unittest.main()
