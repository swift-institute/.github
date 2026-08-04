#!/usr/bin/env python3
"""[CI-117] controls for validate-composite-action-pins.py.

Programme corrigendum §11.1's mandatory positive control (swift-institute/.github#286,
ruled R4/R4a/R4b): "after the change, a deliberate reversion of one site to
`@main` must fail a check." These are that check's own fixtures, proving it
CAN fail before the real-repo assertion below relies on it staying silent:

  - a synthetic workflow with a floating `@main` self-reference fires
    CI-117 and exits 1 (the positive control — the fixture the corrigendum
    requires);
  - the same reference pinned to a 40-hex SHA is silent and exits 0 (the
    conforming/negative control through the same instrument);
  - a short SHA and a tag are both still floating refs and fire (the
    class is "full 40-hex SHA", not "not literally the word main");
  - a reusable-workflow `uses:` line (the permanently-@main class governed
    by [CI-030]/REPO-ACTIONS-004) is never touched by this rule, proving the
    two classes stay distinct in the instrument itself, not only in prose;
  - the real, currently-committed swift-institute/.github workflows have
    zero CI-117 findings — the actual enforcement this suite backs. If a
    future PR reverts a converged site to `@main`, THIS assertion is what
    turns that regression red.

Wired into lint-validator-fixtures.yml beside the other unit-control suites.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "validate-composite-action-pins.py"
REPO_ROOT = Path(__file__).parents[3]

FLOATING_MAIN_WORKFLOW = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: swift-institute/.github/.github/actions/read-orgs@main
"""

PINNED_WORKFLOW = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: swift-institute/.github/.github/actions/read-orgs@6f73c2ebff00e4f05375794905926bdd7a0ca14b  # main 2026-08-04, identity-pin to main HEAD (swift-institute/.github#286)
"""

SHORT_SHA_WORKFLOW = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: swift-institute/.github/.github/actions/read-orgs@6f73c2e
"""

TAG_WORKFLOW = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: swift-institute/.github/.github/actions/read-orgs@v1
"""

REUSABLE_WORKFLOW_MAIN_UNTOUCHED = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
"""

# Same two (file, action) pairs the real validator exempts, plus a THIRD
# action at @main in the same file that is not on the exempt list. Proves
# the exemption is an exact (file, action) pair, not a filename wildcard —
# a different action gaining an unpinned reference in the same file must
# still fire.
EXEMPT_FILE_MIXED_WORKFLOW = """\
name: fixture
on: workflow_dispatch: {}
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: swift-institute/.github/.github/actions/read-orgs@main
      - uses: swift-institute/.github/.github/actions/upsert-tracking-issue@main
      - uses: swift-institute/.github/.github/actions/install-system-deps@main
"""


def run(repo: str, root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), repo, str(root)],
        capture_output=True, text=True,
    )


class CompositeActionPinControls(unittest.TestCase):
    def _write(self, content: str, filename: str = "fixture.yml") -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        wf_dir = root / ".github" / "workflows"
        wf_dir.mkdir(parents=True)
        (wf_dir / filename).write_text(content, encoding="utf-8")
        return root

    def test_floating_main_fires_and_exits_nonzero(self) -> None:
        root = self._write(FLOATING_MAIN_WORKFLOW)
        result = run("swift-institute-test/fixture", root)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("\tCI-117\t", result.stdout)
        self.assertIn("fixture.yml:7", result.stdout)
        self.assertIn("read-orgs@main", result.stdout)

    def test_full_sha_pin_is_silent_and_exits_zero(self) -> None:
        root = self._write(PINNED_WORKFLOW)
        result = run("swift-institute-test/fixture", root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("CI-117", result.stdout)

    def test_short_sha_still_fires(self) -> None:
        root = self._write(SHORT_SHA_WORKFLOW)
        result = run("swift-institute-test/fixture", root)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("\tCI-117\t", result.stdout)

    def test_tag_still_fires(self) -> None:
        root = self._write(TAG_WORKFLOW)
        result = run("swift-institute-test/fixture", root)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("\tCI-117\t", result.stdout)

    def test_reusable_workflow_at_main_is_never_this_rules_finding(self) -> None:
        # The permanently-@main class ([CI-030]/REPO-ACTIONS-004) must stay
        # untouched by this validator. A finding here would mean the two
        # classes bled into each other inside the instrument, not only in
        # the surrounding prose.
        root = self._write(REUSABLE_WORKFLOW_MAIN_UNTOUCHED)
        result = run("swift-institute-test/fixture", root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("CI-117", result.stdout)

    def test_exemption_is_exact_pair_not_filename_wildcard(self) -> None:
        # lint-validators-weekly.yml carries a typed, reasoned exemption for
        # exactly (read-orgs, upsert-tracking-issue) — the two sites this
        # task could not touch because lane 0B-01 holds that file in flight
        # (swift-institute/.github#295). A THIRD action at @main in the same
        # file is not on that list and must still fire: the exemption is a
        # (filename, action) pair, never a blanket pass for the file.
        root = self._write(EXEMPT_FILE_MIXED_WORKFLOW, filename="lint-validators-weekly.yml")
        result = run("swift-institute/.github", root)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("\tCI-117-EXEMPT\t", result.stdout)
        self.assertIn("read-orgs@main", result.stdout)
        self.assertIn("upsert-tracking-issue@main", result.stdout)
        # The exempt lines must not count toward the two exempt actions...
        exempt_lines = [l for l in result.stdout.splitlines() if "\tCI-117-EXEMPT\t" in l]
        self.assertEqual(len(exempt_lines), 2, result.stdout)
        # ...but install-system-deps@main, not on the exempt list, must fire
        # as a normal CI-117 finding and be the thing that makes exit != 0.
        real_findings = [l for l in result.stdout.splitlines() if "\tCI-117\t" in l]
        self.assertEqual(len(real_findings), 1, result.stdout)
        self.assertIn("install-system-deps@main", real_findings[0])

    def test_real_repository_workflows_are_clean(self) -> None:
        # The actual enforcement: every self-referential composite-action
        # `uses:` in the real, currently-committed workflow set must already
        # be identity-pinned. This is the assertion that turns red if a
        # future PR reverts a converged site to `@main` — the corrigendum's
        # mandatory positive control, run against the real tree rather than
        # a synthetic fixture.
        result = run("swift-institute/.github", REPO_ROOT)
        self.assertEqual(
            result.returncode, 0,
            f"real-repo CI-117 findings (expected none):\n{result.stdout}{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
