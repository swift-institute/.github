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


class SecretTransportContractTests(unittest.TestCase):
    """#92-ruling surfaces the repo-shaped ci-059 fixtures cannot reach:
    class-exactness of the typed exemption (the exempt repository with a
    DIFFERENT violation class must still fire — impossible to express as
    a second fixture because the exemption keys the exact repository
    name) and the finding-class tags themselves."""

    def run_validator(
        self, workflow: str, repo: str, sub_org_owner: str | None = None
    ) -> list[str]:
        import tempfile
        from pathlib import Path as _Path

        with tempfile.TemporaryDirectory() as raw:
            root = _Path(raw)
            (root / "Package.swift").write_text(
                "// swift-tools-version: 6.3\n", encoding="utf-8"
            )
            workflows = root / ".github" / "workflows"
            workflows.mkdir(parents=True)
            (workflows / "ci.yml").write_text(workflow, encoding="utf-8")
            if sub_org_owner is not None:
                (root / ".fixture-sub-org-owner").write_text(
                    sub_org_owner, encoding="utf-8"
                )
            output = StringIO()
            with redirect_stdout(output):
                module.main(repo, str(root))
        return output.getvalue().splitlines()

    EXEMPT_REPO = "swift-institute-test/swift-exempt-explicit-caller"

    def test_exempt_repo_admits_only_its_ruled_class(self) -> None:
        # Same repository + path as the typed exemption, but the violation
        # is same-org-omitted, not the admitted same-org-explicit — the
        # exemption must NOT suppress it.
        workflow = """name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
"""
        lines = self.run_validator(workflow, self.EXEMPT_REPO)
        self.assertTrue(any("\tCI-059\t[same-org-omitted]" in l for l in lines), lines)
        self.assertFalse(any("CI-059-EXEMPT" in l for l in lines), lines)

    def test_exempt_repo_admitted_class_reports_exempt_row(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets:
      PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}
"""
        lines = self.run_validator(workflow, self.EXEMPT_REPO)
        self.assertTrue(any("\tCI-059-EXEMPT\t[same-org-explicit]" in l for l in lines), lines)
        self.assertFalse(any("\tCI-059\t" in l for l in lines), lines)

    def test_cross_org_extra_name_is_classified(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  ci:
    uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
    secrets:
      PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}
      SWIFT_INSTITUTE_BOT_APP_CLIENT_ID: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_CLIENT_ID }}
      SWIFT_INSTITUTE_BOT_APP_ID: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_ID }}
      SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}
      EXTRA_DEPLOY_TOKEN: ${{ secrets.EXTRA_DEPLOY_TOKEN }}
"""
        lines = self.run_validator(
            workflow, "swift-institute-test/fixture", sub_org_owner="swift-ietf"
        )
        self.assertTrue(
            any("[cross-org-extra-names]" in l and "EXTRA_DEPLOY_TOKEN" in l for l in lines),
            lines,
        )
        self.assertFalse(any("[cross-org-missing-names]" in l for l in lines), lines)

    def test_cross_org_narrow_and_wide_both_fire(self) -> None:
        workflow = """name: CI
on: [push]
jobs:
  ci:
    uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
    secrets:
      PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}
      EXTRA_DEPLOY_TOKEN: ${{ secrets.EXTRA_DEPLOY_TOKEN }}
"""
        lines = self.run_validator(
            workflow, "swift-institute-test/fixture", sub_org_owner="swift-ietf"
        )
        self.assertTrue(any("[cross-org-missing-names]" in l for l in lines), lines)
        self.assertTrue(any("[cross-org-extra-names]" in l for l in lines), lines)


if __name__ == "__main__":
    unittest.main()
