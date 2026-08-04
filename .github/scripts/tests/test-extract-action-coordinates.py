#!/usr/bin/env python3
"""
Tests for extract-action-coordinates.py (Task 6-01, swift-institute/.github#276).

The script exists because an earlier draft of the effective-runtime
receipt's action-coordinate collection used a regex directly against the
checked-out workflow file's raw text, and matched the literal string
"uses:" inside its OWN embedded script body — a self-scanning false
positive caught by testing against real fetched data, not by inspection.
This suite runs the real script against the real shipped `swift-ci.yml`
(the self-scanning regression control) plus synthetic documents shaped
like each classification and its negation, so every classification this
script can produce is proven reachable and every misclassification this
script must never produce is proven absent.

Usage: python3 .github/scripts/tests/test-extract-action-coordinates.py
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

import yaml

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent
REPO_ROOT = SCRIPTS_DIR.parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "swift-ci.yml"

_spec = importlib.util.spec_from_file_location(
    "extract_action_coordinates", SCRIPTS_DIR / "extract-action-coordinates.py"
)
extract_action_coordinates = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(extract_action_coordinates)


def entries_for(document: dict) -> dict[str, dict]:
    return {e["uses"]: e for e in extract_action_coordinates.extract(document)}


class RealFileSelfScanningRegressionTests(unittest.TestCase):
    """The control this script exists for: run it against the actual
    shipped swift-ci.yml (which, right now, contains THIS suite's own
    docstring and the receipt step's comments mentioning "uses:" in prose)
    and confirm it extracts real `uses:` coordinates only — never a
    fragment of a comment, a docstring, or an embedded script body.
    """

    def setUp(self):
        with open(WORKFLOW, encoding="utf-8") as f:
            self.document = yaml.safe_load(f)
        self.entries = extract_action_coordinates.extract(self.document)

    def test_every_entry_is_a_plausible_uses_coordinate(self):
        # A `uses:` value is always `owner/repo[/path]@ref` or a local
        # `./...` path — never free text, never containing whitespace, and
        # (the specific regression this suite exists to catch) never
        # containing the substring "$u" or "jq" or other script-body debris
        # that a text-regex draft of this script would have picked up from
        # its own source.
        for entry in self.entries:
            with self.subTest(uses=entry["uses"]):
                self.assertNotIn(" ", entry["uses"])
                self.assertNotIn("$", entry["uses"])
                self.assertTrue(
                    entry["uses"].startswith("./")
                    or "/" in entry["uses"],
                )

    def test_every_local_workflow_caller_is_present(self):
        local_callers = {
            e["uses"] for e in self.entries if e["uses"].startswith("./")
        }
        expected = {
            "./.github/workflows/lint-yaml.yml",
            "./.github/workflows/lint-broken-symlink.yml",
            "./.github/workflows/lint-license-header.yml",
            "./.github/workflows/lint-test-support-spine.yml",
            "./.github/workflows/lint-api-breakage.yml",
            "./.github/workflows/lint-pr-title.yml",
        }
        self.assertEqual(local_callers, expected)

    def test_no_entry_is_classified_unpinnable(self):
        # As of this task, every non-local coordinate in swift-ci.yml is a
        # full 40-hex pin — a genuinely unpinnable (mutable third-party
        # tag) entry would be a real fleet-policy violation, not just a
        # receipt curiosity. See test_a_mutable_tag_classifies_unpinnable
        # below for proof this classification still fires when it should.
        unpinnable = [e for e in self.entries if e["classification"] == "unpinnable-recorded"]
        self.assertEqual(unpinnable, [], unpinnable)


class ClassificationTests(unittest.TestCase):
    """Each classification, proven reachable from a synthetic document
    shaped exactly like the case it names — and, for the two structural
    sources (job-level `uses:` vs. step-level `uses:`), proven that both
    are actually collected.
    """

    def test_identity_pinned_full_sha(self):
        doc = {"jobs": {"a": {"steps": [{"uses": "actions/checkout@" + "f" * 40}]}}}
        entries = entries_for(doc)
        self.assertEqual(entries["actions/checkout@" + "f" * 40]["classification"], "identity-pinned")

    def test_reusable_workflow_floating_main(self):
        doc = {"jobs": {"a": {"uses": "swift-institute/.github/.github/workflows/swift-ci.yml@main"}}}
        entries = entries_for(doc)
        self.assertEqual(
            entries["swift-institute/.github/.github/workflows/swift-ci.yml@main"]["classification"],
            "reusable-workflow-floating-main",
        )

    def test_local_reusable_workflow_no_ref(self):
        doc = {"jobs": {"a": {"uses": "./.github/workflows/lint-yaml.yml"}}}
        entries = entries_for(doc)
        self.assertEqual(
            entries["./.github/workflows/lint-yaml.yml"]["classification"],
            "local-reusable-workflow",
        )
        self.assertEqual(entries["./.github/workflows/lint-yaml.yml"]["ref"], "")

    def test_a_mutable_tag_classifies_unpinnable(self):
        """Positive control: the exact hazard [CI-117]/branch-pin policy
        exists to keep out of this fleet — a third-party or composite
        action pinned to a mutable tag rather than a full SHA — must still
        be classified (not silently dropped, not misclassified as pinned)."""
        doc = {"jobs": {"a": {"steps": [{"uses": "actions/checkout@v4"}]}}}
        entries = entries_for(doc)
        self.assertEqual(entries["actions/checkout@v4"]["classification"], "unpinnable-recorded")

    def test_short_sha_is_not_identity_pinned(self):
        """Positive control: a short (7-char) SHA looks superficially like
        a commit reference but is not the required full 40-hex form."""
        doc = {"jobs": {"a": {"steps": [{"uses": "actions/checkout@abc1234"}]}}}
        entries = entries_for(doc)
        self.assertEqual(entries["actions/checkout@abc1234"]["classification"], "unpinnable-recorded")

    def test_job_level_uses_is_collected(self):
        doc = {"jobs": {"a": {"uses": "./.github/workflows/x.yml"}}}
        self.assertEqual(len(extract_action_coordinates.extract(doc)), 1)

    def test_step_level_uses_is_collected(self):
        doc = {"jobs": {"a": {"steps": [{"uses": "actions/checkout@" + "a" * 40}]}}}
        self.assertEqual(len(extract_action_coordinates.extract(doc)), 1)

    def test_both_job_and_step_level_uses_in_the_same_document(self):
        doc = {
            "jobs": {
                "a": {"uses": "./.github/workflows/x.yml"},
                "b": {"steps": [{"uses": "actions/checkout@" + "a" * 40}]},
            }
        }
        self.assertEqual(len(extract_action_coordinates.extract(doc)), 2)

    def test_a_step_with_no_uses_is_not_collected(self):
        doc = {"jobs": {"a": {"steps": [{"run": "echo uses: bogus"}]}}}
        # The exact regression this suite exists to catch, reproduced
        # directly: a `run:` step body that CONTAINS the text "uses:" must
        # never be picked up, because it is read as one opaque string, not
        # walked for keys.
        self.assertEqual(extract_action_coordinates.extract(doc), [])

    def test_duplicate_uses_across_jobs_is_deduplicated(self):
        doc = {
            "jobs": {
                "a": {"steps": [{"uses": "actions/checkout@" + "a" * 40}]},
                "b": {"steps": [{"uses": "actions/checkout@" + "a" * 40}]},
            }
        }
        self.assertEqual(len(extract_action_coordinates.extract(doc)), 1)


class CommandLineTests(unittest.TestCase):
    def test_running_against_a_temp_file_produces_valid_json(self):
        import json
        import subprocess
        import sys

        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "wf.yml"
            path.write_text(
                "jobs:\n  a:\n    steps:\n      - uses: actions/checkout@" + "a" * 40 + "\n",
                encoding="utf-8",
            )
            completed = subprocess.run(
                [sys.executable, str(SCRIPTS_DIR / "extract-action-coordinates.py"), str(path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertEqual(len(parsed), 1)

    def test_wrong_argument_count_fails_with_usage(self):
        import subprocess
        import sys

        completed = subprocess.run(
            [sys.executable, str(SCRIPTS_DIR / "extract-action-coordinates.py")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("usage:", completed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
