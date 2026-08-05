#!/usr/bin/env python3
"""Tests for the effective-runtime-receipt subsystem (TX7 receipt contract,
swift-institute/.github#276 §8.9; predicates P19/P20).

The P20 mandatory negative control lives here: the empty-referenced-
workflows case must FAIL against the historical false-success variant
(reproduced via `strict_referenced_workflows=False`) and pass — i.e.
be correctly refused — against the shipped strict helper.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent

def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

receipt = _load("effective_runtime_receipt", "effective-runtime-receipt.py")
readiness = _load("validate_completion_receipt", "validate-completion-receipt.py")


def sample_run(**overrides):
    run = {
        "id": 31000000001,
        "run_attempt": 1,
        "conclusion": None,
        "event": "workflow_dispatch",
        "path": ".github/workflows/swift-ci.yml",
        "head_sha": "9a049de38e4ab925ce3edefdf1cd1b67428565c5",
        "head_branch": "main",
        "repository": {"full_name": "swift-institute/.github"},
        "head_repository": {"full_name": "swift-institute/.github"},
        "actor": {"login": "swift-institute-bot[bot]"},
        "referenced_workflows": [
            {
                "path": "swift-institute/.github/.github/workflows/swift-ci.yml@refs/heads/main",
                "ref": "refs/heads/main",
                "sha": "86631ee613f0032c5d395313a2e3253840fb1673",
            }
        ],
    }
    run.update(overrides)
    return run


def sample_jobs():
    return [
        {"id": 1, "name": "plan", "conclusion": "success", "labels": ["ubuntu-latest"]},
        {"id": 2, "name": "macos-release build+test", "conclusion": None, "labels": ["macos-26"]},
        {"id": 3, "name": "lint-yaml advisory", "conclusion": "skipped", "labels": ["ubuntu-latest"]},
    ]


GATING = ["plan", "macos-release"]


def build(run=None, jobs=None, **kwargs):
    return receipt.build_base_record(
        run or sample_run(),
        jobs or sample_jobs(),
        planned_gating=GATING,
        subject_repository="swift-foundations/swift-copy-on-write",
        subject_sha="a" * 40,
        subject_visibility="public",
        **kwargs,
    )


class BaseRecordTests(unittest.TestCase):
    def test_deterministic_canonical_bytes_and_digest(self):
        a, _ = build()
        b, _ = build()
        self.assertEqual(receipt.canonical_bytes(a), receipt.canonical_bytes(b))
        self.assertEqual(receipt.digest(a), receipt.digest(b))

    def test_changed_input_changes_the_digest(self):
        a, _ = build()
        b, _ = build(run=sample_run(head_sha="b" * 40))
        self.assertNotEqual(receipt.digest(a), receipt.digest(b))

    def test_top_level_keys_are_exactly_the_declared_thirteen(self):
        record, _ = build()
        self.assertEqual(
            sorted(record),
            sorted(
                [
                    "schemaVersion", "attestationStage", "baseReceiptDigest",
                    "run", "subject", "referencedWorkflows", "actions",
                    "containers", "linter", "jobs", "revisions", "verdict",
                    "unmeasured",
                ]
            ),
        )

    def test_preterminal_null_conclusions_are_paired_with_unmeasured_rows(self):
        record, ok = build()
        self.assertTrue(ok)
        fields = {u["field"] for u in record["unmeasured"]}
        self.assertIn("run.conclusion", fields)
        self.assertIn("jobs[2].conclusion", fields)
        self.assertEqual(record["attestationStage"], "preterminal")
        self.assertIsNone(record["baseReceiptDigest"])

    def test_p20_empty_chain_fails_strict_and_passed_the_historical_variant(self):
        """The mandatory P20 control. The HISTORICAL false-success variant
        accepts the empty reusable-workflow chain as clean; the shipped
        strict helper refuses it (ok=False, verdict UNMEASURED)."""
        empty = sample_run(referenced_workflows=[])
        broken_record, broken_ok = build(run=empty, strict_referenced_workflows=False)
        self.assertTrue(broken_ok, "historical variant falsely accepts the empty chain")
        self.assertEqual(broken_record["verdict"], "preterminal")

        strict_record, strict_ok = build(run=empty)
        self.assertFalse(strict_ok, "strict helper must fail the aggregate on an empty chain")
        self.assertEqual(strict_record["verdict"], "UNMEASURED")
        self.assertIn(
            "referencedWorkflows", {u["field"] for u in strict_record["unmeasured"]}
        )


class ReadinessValidatorTests(unittest.TestCase):
    def _terminal(self, **mutations):
        record, _ = build()
        record["attestationStage"] = "terminal"
        record["baseReceiptDigest"] = "0" * 64
        record["run"]["conclusion"] = "success"
        for row in record["jobs"]:
            row["conclusion"] = row["conclusion"] or "success"
        record["unmeasured"] = [
            u for u in record["unmeasured"] if not u["field"].endswith("conclusion")
        ]
        record["verdict"] = "MET"
        record.update(mutations)
        return record

    def _validate(self, record):
        raw = receipt.canonical_bytes(record)
        return readiness.validate_runtime(record, raw, "terminal", True)

    def test_a_clean_terminal_met_receipt_is_accepted(self):
        self.assertEqual(self._validate(self._terminal()), [])

    def test_preterminal_stage_is_rejected(self):
        record = self._terminal(attestationStage="preterminal", baseReceiptDigest=None)
        self.assertIn("STAGE-NOT-TERMINAL", self._validate(record))

    def test_null_terminal_conclusion_without_unmeasured_row_is_rejected(self):
        record = self._terminal()
        record["run"]["conclusion"] = None
        findings = self._validate(record)
        self.assertIn("NULL-TERMINAL-FIELD", findings)

    def test_local_path_is_rejected(self):
        record = self._terminal()
        record["subject"]["repository"] = "/Users/somebody/checkout"
        self.assertIn("LOCAL-PATH", self._validate(record))

    def test_short_sha_is_rejected(self):
        record = self._terminal()
        record["subject"]["sha"] = "abc123"
        self.assertIn("SHORT-SHA", self._validate(record))


class CliTests(unittest.TestCase):
    def test_cli_emits_canonical_file_digest_and_zero_exit(self):
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            run_path = Path(raw) / "run.json"
            jobs_path = Path(raw) / "jobs.json"
            out_path = Path(raw) / "receipt.base.json"
            run_path.write_text(json.dumps(sample_run()), encoding="utf-8")
            jobs_path.write_text(json.dumps({"jobs": sample_jobs()}), encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable, str(SCRIPTS_DIR / "effective-runtime-receipt.py"),
                    "--run-json", str(run_path), "--jobs-json", str(jobs_path),
                    "--planned-gating", ",".join(GATING),
                    "--subject-repository", "swift-foundations/swift-copy-on-write",
                    "--subject-sha", "a" * 40,
                    "--subject-visibility", "public",
                    "--output", str(out_path),
                ],
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            record = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertEqual(record["attestationStage"], "preterminal")
            declared = (out_path.parent / "receipt.base.json.sha256").read_text().strip()
            import hashlib
            self.assertEqual(declared, hashlib.sha256(out_path.read_bytes()).hexdigest())

    def test_cli_exits_nonzero_on_the_empty_chain(self):
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            run_path = Path(raw) / "run.json"
            jobs_path = Path(raw) / "jobs.json"
            out_path = Path(raw) / "receipt.base.json"
            run_path.write_text(json.dumps(sample_run(referenced_workflows=[])), encoding="utf-8")
            jobs_path.write_text(json.dumps({"jobs": sample_jobs()}), encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable, str(SCRIPTS_DIR / "effective-runtime-receipt.py"),
                    "--run-json", str(run_path), "--jobs-json", str(jobs_path),
                    "--planned-gating", ",".join(GATING),
                    "--subject-repository", "swift-foundations/swift-copy-on-write",
                    "--subject-sha", "a" * 40,
                    "--subject-visibility", "public",
                    "--output", str(out_path),
                ],
                capture_output=True, text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("UNMEASURED", out_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
