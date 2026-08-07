#!/usr/bin/env python3
# TRANSFERRED: this predicate's Swift realisation is owned by the Foundation
# Programme's TX-APP1W (CW transfer ruling: swift-institute/.github#358
# comment 5215227317; migration preimage: comment 5215128447). This file is
# retained verbatim until its Swift owner's activation receipt; its deletion
# rides that gate. Do not port, modify, or delete it under Goal #358.

"""test-validate-completion-receipt.py — dedicated §13.3 rejection suite.

Observes every mandated rejection: preterminal stage, null terminal
conclusion, base/run attempt/head mismatch, incomplete pagination,
skipped/cancelled mandatory job, short SHA, machine path, private
coordinate leak (via the opaqueness proposition), missing positive
control, missing receipt table/assertion, nonterminal predicate — plus
passing positive controls for both modes and both phases.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "validate-completion-receipt.py")
if not os.path.exists(SCRIPT):
    SCRIPT = os.path.join(HERE, "validate-completion-receipt.py")

SHA40 = "a" * 40
HEX = "b" * 64


def good_runtime() -> dict:
    return {
        "schemaVersion": 1,
        "attestationStage": "terminal",
        "baseReceiptDigest": HEX,
        "run": {"repository": "org/repo", "id": 1, "attempt": 1,
                "headSha": SHA40, "conclusion": "success"},
        "subject": {"repository": "org/repo", "sha": SHA40},
        "referencedWorkflows": [{"path": "x.yml", "ref": "main", "sha": SHA40}],
        "jobs": [{"id": 10, "name": "ci-ok", "conclusion": "success",
                  "selected": True, "mandatory": True}],
        "jobsTotalCount": 1,
        "verdict": "MET",
        "unmeasured": [],
    }


def good_inputs(readiness_digest: str) -> dict:
    preds = {f"P{i}": {"state": "MET"} for i in range(1, 27)}
    preds["P21"] = {"state": "DESCOPED"}
    preds["P14"] = {"state": "MET (public/control limbs) + DESCOPED (private-ruleset limb)",
                    "ruling": "R33"}
    preds["P27"] = {"nonPerformativeLimbsSupportable": True}
    preds["P28"] = {"nonPerformativeLimbsSupportable": True}
    tables = [{"name": f"table-{i}", "populated": True} for i in range(1, 17)]
    tables[7]["nameReservationField"] = True
    return {
        "authority": {
            "refactorProgramme": "184db8ef230cd7e532f9aeb167a51508bc897f8221ec935cb5a776ca1eaf62ef",
            "completionProgramme": "62e315c42f6ec6b34320af560697fc8bfb772ab655ddc4c65456ff04cd90d21f",
        },
        "predicates": preds,
        "tables": tables,
        "workspaceReconciliation": [{"item": "x", "state": "reconciled"}],
        "assertions": [{"n": i, "supportable": True} for i in range(1, 17)],
        "positiveControls": [{"name": "census-instrument", "fired": True}],
        "compatibilityRemoved": True,
        "holdsRemoved": True,
        "destructiveOperationsAccounted": True,
        "fleetDispositionImplemented": True,
        "fleetDispositionAuthorized": True,
        "privateCoordinatesOpaque": True,
        "performativeAmendment": {"located": True, "ruling": "R29"},
        "externalReview": {"verdict": "ACCEPTED FOR R1"},
        "receiptCandidateDigest": HEX,
        "runtimeReceipts": [{"runId": 1, "runAttempt": 1, "headSha": SHA40,
                             "digest": readiness_digest}],
    }


class Harness(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def path(self, name):
        return os.path.join(self.root, name)

    def write(self, name, obj):
        p = self.path(name)
        with open(p, "w") as f:
            json.dump(obj, f)
        return p

    def run_mode(self, *argv):
        out = self.path("out.json")
        proc = subprocess.run([sys.executable, SCRIPT, *argv, "--output", out],
                              capture_output=True, text=True)
        result = None
        if os.path.exists(out):
            with open(out) as f:
                result = json.load(f)
        return proc.returncode, result

    def runtime(self, record):
        p = self.write("receipt.json", record)
        return self.run_mode("runtime", "--runtime-receipt", p,
                             "--require-stage", "terminal", "--require-completed-run")

    def readiness_for(self, record):
        raw = json.dumps(record).encode()
        digest = hashlib.sha256(raw).hexdigest()
        os.makedirs(self.path("ready"), exist_ok=True)
        rec = {"schemaVersion": 1, "mode": "runtime", "result": "PASS", "findings": [],
               "evidence": [{"runId": 1, "runAttempt": 1, "headSha": SHA40,
                             "terminalReceiptDigest": digest}]}
        with open(self.path("ready/runtime-1-1.json"), "w") as f:
            json.dump(rec, f)
        return digest

    def completion(self, inputs, phase="pre-finalization", link=None):
        p = self.write("inputs.json", inputs)
        argv = ["completion", "--phase", phase, "--receipt-input", p,
                "--runtime-readiness-dir", self.path("ready")]
        if link is not None:
            argv += ["--link-readback", self.write("link.json", link)]
        return self.run_mode(*argv)


class RuntimeMode(Harness):
    def test_pass(self):
        code, result = self.runtime(good_runtime())
        self.assertEqual((code, result["result"]), (0, "PASS"))
        self.assertEqual(result["mode"], "runtime")
        self.assertNotIn("/", json.dumps(result["evidence"]))

    def test_rejects_preterminal_stage(self):
        r = good_runtime(); r["attestationStage"] = "preterminal"; r["baseReceiptDigest"] = None
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("STAGE-NOT-TERMINAL", [f["code"] for f in result["findings"]])

    def test_rejects_null_terminal_conclusion(self):
        r = good_runtime(); r["run"]["conclusion"] = None
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("NULL-TERMINAL-FIELD", [f["code"] for f in result["findings"]])

    def test_rejects_skipped_mandatory_job(self):
        r = good_runtime(); r["jobs"][0]["conclusion"] = "skipped"
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("MANDATORY-JOB-NOT-SUCCESS", [f["code"] for f in result["findings"]])

    def test_rejects_cancelled_mandatory_job(self):
        r = good_runtime(); r["jobs"][0]["conclusion"] = "cancelled"
        code, _ = self.runtime(r)
        self.assertEqual(code, 1)

    def test_rejects_incomplete_pagination(self):
        r = good_runtime(); r["jobsTotalCount"] = 2
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("JOBS-PAGINATION-INCOMPLETE", [f["code"] for f in result["findings"]])

    def test_rejects_short_sha(self):
        r = good_runtime(); r["run"]["headSha"] = "abc123"
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("SHORT-SHA", [f["code"] for f in result["findings"]])

    def test_rejects_machine_path(self):
        r = good_runtime(); r["subject"]["note"] = "/Users/nobody/checkout"
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("LOCAL-PATH", [f["code"] for f in result["findings"]])

    def test_rejects_non_met_verdict(self):
        r = good_runtime(); r["verdict"] = "UNMEASURED"
        code, result = self.runtime(r)
        self.assertEqual(code, 1)
        self.assertIn("RUNTIME-RECEIPT-REJECTED", [f["code"] for f in result["findings"]])

    def test_unreadable_is_exit_2(self):
        code, _ = self.run_mode("runtime", "--runtime-receipt", self.path("absent.json"))
        self.assertEqual(code, 2)


class CompletionMode(Harness):
    def setUp(self):
        super().setUp()
        self.receipt = good_runtime()
        self.digest = self.readiness_for(self.receipt)

    def test_pre_finalization_pass(self):
        code, result = self.completion(good_inputs(self.digest))
        self.assertEqual((code, result["result"]), (0, "PASS"))
        self.assertEqual(result["evidence"][0]["terminalReceiptDigest"], self.digest)

    def test_rejects_nonterminal_predicate(self):
        i = good_inputs(self.digest); i["predicates"]["P5"] = {"state": "UNMEASURED"}
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("PREDICATE-NOT-TERMINAL", [f["code"] for f in result["findings"]])

    def test_rejects_met_with_descoped_limb_without_ruling(self):
        i = good_inputs(self.digest)
        i["predicates"]["P14"] = {"state": "MET (public) + DESCOPED (private limb)"}
        code, _ = self.completion(i)
        self.assertEqual(code, 1)

    def test_rejects_missing_table(self):
        i = good_inputs(self.digest); i["tables"][3]["populated"] = False
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("RECEIPT-STRUCTURE-INCOMPLETE", [f["code"] for f in result["findings"]])

    def test_rejects_missing_name_reservation_field(self):
        i = good_inputs(self.digest); del i["tables"][7]["nameReservationField"]
        code, _ = self.completion(i)
        self.assertEqual(code, 1)

    def test_rejects_missing_assertion(self):
        i = good_inputs(self.digest); i["assertions"][15]["supportable"] = False
        code, _ = self.completion(i)
        self.assertEqual(code, 1)

    def test_rejects_missing_positive_control(self):
        i = good_inputs(self.digest); i["positiveControls"] = []
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("MISSING-POSITIVE-CONTROL", [f["code"] for f in result["findings"]])

    def test_rejects_private_coordinate_leak_proposition(self):
        i = good_inputs(self.digest); i["privateCoordinatesOpaque"] = False
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("PROPOSITION-FALSE", [f["code"] for f in result["findings"]])

    def test_rejects_binding_mismatch(self):
        i = good_inputs(self.digest)
        i["runtimeReceipts"][0]["headSha"] = "c" * 40
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("RECEIPT-BINDING-MISMATCH", [f["code"] for f in result["findings"]])

    def test_missing_readiness_is_exit_2(self):
        i = good_inputs(self.digest)
        i["runtimeReceipts"].append({"runId": 9, "runAttempt": 1, "headSha": SHA40, "digest": HEX})
        code, result = self.completion(i)
        self.assertEqual(code, 2)
        self.assertIn("READINESS-UNAVAILABLE", [f["code"] for f in result["findings"]])

    def test_rejects_unaccepted_external_review(self):
        i = good_inputs(self.digest); i["externalReview"] = {"verdict": "REJECTED — R1 BLOCKED"}
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("EXTERNAL-REVIEW-NOT-ACCEPTED", [f["code"] for f in result["findings"]])

    def test_rejects_wrong_authority_digest(self):
        i = good_inputs(self.digest); i["authority"]["completionProgramme"] = HEX
        code, result = self.completion(i)
        self.assertEqual(code, 1)
        self.assertIn("AUTHORITY-NOT-VERIFIED", [f["code"] for f in result["findings"]])

    def test_post_finalization_pass_and_rejections(self):
        i = good_inputs(self.digest)
        i["predicates"]["P27"] = {"state": "MET"}
        i["predicates"]["P28"] = {"state": "MET"}
        link = {"goalState": "closed", "goalStateReason": "completed",
                "receiptCommit": SHA40, "receiptSha256": HEX, "linkCommentId": 123}
        code, result = self.completion(i, phase="post-finalization", link=link)
        self.assertEqual((code, result["result"]), (0, "PASS"))
        bad = dict(link, goalState="open")
        code, result = self.completion(i, phase="post-finalization", link=bad)
        self.assertEqual(code, 1)
        short = dict(link, receiptCommit="abc123")
        code, result = self.completion(i, phase="post-finalization", link=short)
        self.assertEqual(code, 1)
        self.assertIn("SHORT-SHA", [f["code"] for f in result["findings"]])
        code, result = self.completion(i, phase="post-finalization", link=None)
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
