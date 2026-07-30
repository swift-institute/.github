#!/usr/bin/env python3
"""Baseline-contract controls for validate-branch-pins.py.

run.sh's repo-shaped fixtures prove the detector itself (fires on branch
pins, silent on versions / foreign orgs / comments). What they cannot
reach is the guard contract layered on top: baseline suppression, the
exit code the swift-ci fast-check keys on, and the --orgs-file override
that fast-check depends on after copying the script out of its checkout.
These tests exercise exactly that surface:

  - a baselined (repo, url) pair reports BRANCH-PIN-BASELINE and exits 0;
  - a declaration ABSENT from the baseline still fires BRANCH-PIN-001 and
    exits 1 — the guard's own positive control, so a broken baseline
    filter cannot silently admit new pins;
  - a near-miss baseline entry (same url, different repo) does NOT
    suppress; a missing baseline file is an empty baseline;
  - --orgs-file resolves the org set when the script runs outside a full
    checkout.

Wired into lint-validator-fixtures.yml beside run.sh.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "validate-branch-pins.py"
ORGS = Path(__file__).parents[2] / "actions" / "read-orgs" / "orgs.yaml"

MANIFEST = """// swift-tools-version: 6.3
import PackageDescription
let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-pinned.git", branch: "main"),
    ],
    targets: [.target(name: "Fixture")]
)
"""


def run(repo: str, root: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), repo, str(root), "--orgs-file", str(ORGS), *extra],
        capture_output=True, text=True,
    )


class BaselineContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "Package.swift").write_text(MANIFEST, encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_baseline(self, *lines: str) -> Path:
        path = self.root / "baseline.tsv"
        path.write_text("# test baseline\n" + "".join(f"{l}\n" for l in lines), encoding="utf-8")
        return path

    def test_no_baseline_fires_and_exits_nonzero(self) -> None:
        result = run("swift-primitives/consumer", self.root)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("\tBRANCH-PIN-001\t", result.stdout)

    def test_baselined_pair_is_informational_and_exits_zero(self) -> None:
        baseline = self.write_baseline(
            "swift-primitives/consumer\thttps://github.com/swift-primitives/swift-pinned.git"
        )
        result = run("swift-primitives/consumer", self.root, "--baseline", str(baseline))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("\tBRANCH-PIN-BASELINE\t", result.stdout)
        self.assertNotIn("\tBRANCH-PIN-001\t", result.stdout)

    def test_declaration_absent_from_baseline_still_fires(self) -> None:
        # The guard's positive control: a populated baseline that does NOT
        # contain this declaration must not suppress it.
        baseline = self.write_baseline(
            "swift-primitives/consumer\thttps://github.com/swift-primitives/swift-unrelated.git"
        )
        result = run("swift-primitives/consumer", self.root, "--baseline", str(baseline))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("\tBRANCH-PIN-001\t", result.stdout)

    def test_same_url_different_repo_does_not_suppress(self) -> None:
        baseline = self.write_baseline(
            "swift-primitives/other-consumer\thttps://github.com/swift-primitives/swift-pinned.git"
        )
        result = run("swift-primitives/consumer", self.root, "--baseline", str(baseline))
        self.assertEqual(result.returncode, 1)
        self.assertIn("\tBRANCH-PIN-001\t", result.stdout)

    def test_missing_baseline_file_is_empty_baseline(self) -> None:
        result = run("swift-primitives/consumer", self.root,
                     "--baseline", str(self.root / "does-not-exist.tsv"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("\tBRANCH-PIN-001\t", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
