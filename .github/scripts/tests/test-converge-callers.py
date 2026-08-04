#!/usr/bin/env python3
"""
Tests for converge-callers.py (Task 5-02, swift-institute/.github#276, #282,
ruling R23a).

Three evidence classes, matching the script's own docstring properties:

  - ClassifyRepoTests: the census/disposition logic against synthetic
    GraphQL search-result nodes (no network) — every disposition class the
    acceptance predicate names (converged, needs-convergence, typed
    exceptions for archived/no-caller/unknown-customization/unresolvable-
    layer, out-of-scope) plus the positive control that a genuinely
    divergent caller is classified for repair while byte-identical output
    is classified as already converged.
  - Goal90CheckTests / PreconditionTests: the machine-checkable-precondition
    parsing logic against synthetic API payloads, including the negative
    control that a stale/empty response never gets silently read as
    "established" (R15.1).
  - RateLimitedGhTests: the secondary-rate-limit backoff and quota-
    checkpoint logic against a stubbed subprocess, including the positive
    control that a 403 "secondary rate limit" response is retried (not
    immediately raised) and the negative control that an ordinary failure
    is NOT retried into a false eventual success.

Live/offline round-trip coverage against the real generator and validator
(self_verify) is exercised manually in the Task 5-02 receipt against a
real, currently-live repository — see receipts/5-02.md — because it shells
out to validate-thin-callers.py and is best proven against real drift
rather than a synthetic fixture that could encode the same wrong
expectation as the code under test.

Usage: python3 .github/scripts/tests/test-converge-callers.py
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent

# Same hyphenated-filename loading trick as test-generate-caller.py: the
# module must be registered in sys.modules BEFORE exec_module, or
# dataclass field resolution raises under this local Python's `_is_type`
# (an artifact of loading a hyphenated module for testing, not something
# `python3 converge-callers.py ...` ever hits).
_gc_spec = importlib.util.spec_from_file_location("generate_caller", SCRIPTS_DIR / "generate-caller.py")
generate_caller = importlib.util.module_from_spec(_gc_spec)
sys.modules["generate_caller"] = generate_caller
_gc_spec.loader.exec_module(generate_caller)

_cc_spec = importlib.util.spec_from_file_location("converge_callers", SCRIPTS_DIR / "converge-callers.py")
converge_callers = importlib.util.module_from_spec(_cc_spec)
sys.modules["converge_callers"] = converge_callers
_cc_spec.loader.exec_module(converge_callers)


def _node(**overrides):
    base = {
        "nameWithOwner": "swift-primitives/swift-example",
        "isArchived": False,
        "isPrivate": False,
        "defaultBranchRef": {"name": "main"},
        "pkg": {"oid": "deadbeef"},
        "caller": None,
        "formatWorkflow": None,
        "swiftlintWorkflow": None,
    }
    base.update(overrides)
    return base


CANONICAL_SAME_ORG = generate_caller.generate(
    generate_caller.CallerSpec(repository="swift-primitives/swift-example", layer="primitives")
)


def _check_suite(*names):
    return {"checkRuns": {"nodes": [{"name": n} for n in names]}}


class EmitsMatrixCiOkTests(unittest.TestCase):
    """Coordinator-directed column (2026-08-04): whether a repository's
    default-branch head currently produces the `ci / matrix / ci-ok`
    check-run name — read from the same batched GraphQL page as the rest
    of the census, never a per-repository REST fan-out."""

    def test_private_repository_is_not_applicable(self):
        self.assertEqual(
            converge_callers.emits_matrix_ci_ok(_node(isPrivate=True)), "not-applicable-private"
        )

    def test_emits_when_the_name_is_present_among_check_runs(self):
        """Positive control, matching the coordinator's own live
        verification on swift-copy-on-write: the name appears inside a
        check suite alongside many other run names."""
        node = _node(defaultBranchRef={
            "name": "main",
            "target": {"checkSuites": {"nodes": [
                _check_suite("ci / ci-ok", "ci / matrix / ci-ok", "ci / matrix / SwiftLint"),
            ]}},
        })
        self.assertEqual(converge_callers.emits_matrix_ci_ok(node), "emits")

    def test_does_not_emit_when_suites_exist_but_lack_the_name(self):
        """Negative control: check suites ARE present (so this is a real
        read, not a missing-data case) but the exact required name is
        absent — the divergent/bespoke-workflow population the coordinator
        asked to be enumerated, not assumed empty."""
        node = _node(defaultBranchRef={
            "name": "main",
            "target": {"checkSuites": {"nodes": [_check_suite("build", "test")]}},
        })
        self.assertEqual(converge_callers.emits_matrix_ci_ok(node), "does-not-emit")

    def test_no_check_suites_is_unmeasured_not_does_not_emit(self):
        """R10 / zero-result protocol: a repository that has simply never
        run a workflow at its default-branch head is UNMEASURED, never
        silently folded into the same bucket as one whose workflow ran and
        genuinely lacks the aggregate."""
        node = _node(defaultBranchRef={"name": "main", "target": {"checkSuites": {"nodes": []}}})
        result = converge_callers.emits_matrix_ci_ok(node)
        self.assertNotEqual(result, "does-not-emit")
        self.assertIn("UNMEASURED", result)

    def test_no_target_commit_is_unmeasured(self):
        node = _node(defaultBranchRef={"name": "main", "target": None})
        result = converge_callers.emits_matrix_ci_ok(node)
        self.assertIn("UNMEASURED", result)


class ClassifyRepoTests(unittest.TestCase):
    def test_archived_repository_is_a_typed_exception(self):
        _, exc = converge_callers.classify_repo(_node(isArchived=True), generate_caller)
        self.assertIsNotNone(exc)
        self.assertEqual(exc.reason_code, "archived")

    def test_no_package_swift_is_out_of_scope_not_an_exception(self):
        """A control-plane / non-package repository (e.g. an org's `.github`)
        is never an exception: it was never a convergence candidate."""
        disp, exc = converge_callers.classify_repo(_node(pkg=None), generate_caller)
        self.assertIsNone(exc)
        self.assertEqual(disp.outcome, "out-of-scope")

    def test_missing_caller_file_is_a_typed_exception(self):
        _, exc = converge_callers.classify_repo(_node(caller=None), generate_caller)
        self.assertIsNotNone(exc)
        self.assertEqual(exc.reason_code, "no-caller-file")

    def test_unresolvable_layer_is_a_typed_exception(self):
        """Positive control: a `uses:` line pointing at an org this
        generator does not know as a layer wrapper must be reported, never
        silently guessed at (5-01 Change item 5's discipline extended)."""
        caller_text = (
            "jobs:\n  ci:\n    uses: some-unknown-org/.github/.github/workflows/swift-ci.yml@main\n"
            "    secrets: inherit\n  docs:\n    uses: some-unknown-org/.github/.github/workflows/swift-docs.yml@main\n"
            "    secrets: inherit\n"
        )
        _, exc = converge_callers.classify_repo(
            _node(caller={"text": caller_text, "isBinary": False}), generate_caller
        )
        self.assertIsNotNone(exc)
        self.assertEqual(exc.reason_code, "layer-unresolvable")

    def test_unknown_customization_is_a_typed_exception_naming_the_cause(self):
        """Positive control mirroring generate-caller.py's own: an
        unapproved `with:` key must be reported, never silently dropped."""
        caller_text = (
            "jobs:\n  ci:\n    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main\n"
            "    with:\n      bespoke-input: yes\n    secrets: inherit\n"
            "  docs:\n    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main\n"
            "    secrets: inherit\n"
        )
        _, exc = converge_callers.classify_repo(
            _node(caller={"text": caller_text, "isBinary": False}), generate_caller
        )
        self.assertIsNotNone(exc)
        self.assertEqual(exc.reason_code, "unknown-customization")
        self.assertIn("bespoke-input", exc.reason_detail)

    def test_byte_identical_caller_is_converged(self):
        disp, exc = converge_callers.classify_repo(
            _node(caller={"text": CANONICAL_SAME_ORG, "isBinary": False}), generate_caller
        )
        self.assertIsNone(exc)
        self.assertEqual(disp.outcome, "converged")

    def test_divergent_caller_needs_convergence_and_carries_a_spec(self):
        """The real-world positive control observed live against
        swift-arm-ltd/swift-arm-standard (receipt): a caller that differs
        only in explanatory comments still parses to a valid spec and is
        classified for repair, never silently accepted as equivalent."""
        drifted = CANONICAL_SAME_ORG.replace(
            "jobs:\n  ci:", "jobs:\n  # explanatory prose the generator will not reproduce\n  ci:"
        )
        disp, exc = converge_callers.classify_repo(
            _node(caller={"text": drifted, "isBinary": False}), generate_caller
        )
        self.assertIsNone(exc)
        self.assertEqual(disp.outcome, "needs-convergence")
        self.assertEqual(disp.spec["layer"], "primitives")

    def test_standalone_format_or_lint_workflow_forces_convergence_even_if_ci_yml_matches(self):
        disp, exc = converge_callers.classify_repo(
            _node(caller={"text": CANONICAL_SAME_ORG, "isBinary": False}, formatWorkflow={"oid": "x"}),
            generate_caller,
        )
        self.assertIsNone(exc)
        self.assertEqual(disp.outcome, "needs-convergence")
        self.assertTrue(disp.delete_standalone)

    def test_cross_org_repository_recovers_the_four_secret_spec(self):
        cross_org_canonical = generate_caller.generate(
            generate_caller.CallerSpec(repository="swift-ietf/swift-example", layer="standards")
        )
        disp, exc = converge_callers.classify_repo(
            _node(
                nameWithOwner="swift-ietf/swift-example",
                caller={"text": cross_org_canonical, "isBinary": False},
            ),
            generate_caller,
        )
        self.assertIsNone(exc)
        self.assertEqual(disp.outcome, "converged")
        self.assertEqual(disp.layer, "standards")


class Goal90CheckTests(unittest.TestCase):
    def test_clear_when_issue_untouched_and_no_same_day_merges(self):
        gh = mock.Mock()
        old = (datetime.now(timezone.utc) - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ")
        gh.api.side_effect = [
            {"state": "OPEN", "updated_at": old},
            {"total_count": 0},
        ]
        result = converge_callers.check_goal_90(gh)
        self.assertEqual(result.verdict, "clear")

    def test_renewed_dispatch_suspected_when_recently_touched_and_merges_exist(self):
        """Positive control: the exact condition the document's own
        preconditions ask this check to catch must actually flip the
        verdict, not just be present in the detail string."""
        gh = mock.Mock()
        recent = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        gh.api.side_effect = [
            {"state": "OPEN", "updated_at": recent},
            {"total_count": 3},
        ]
        result = converge_callers.check_goal_90(gh)
        self.assertEqual(result.verdict, "renewed-dispatch-suspected")

    def test_unreadable_issue_is_unmeasured_never_clear(self):
        """R10/zero-result protocol: inaccessible input is UNMEASURED, never
        silently converted into a passing 'clear' verdict."""
        gh = mock.Mock()
        gh.api.side_effect = converge_callers.GhCallFailed("boom")
        result = converge_callers.check_goal_90(gh)
        self.assertEqual(result.verdict, "unmeasured")
        self.assertEqual(result.state, "UNMEASURED")


class PreconditionTests(unittest.TestCase):
    def test_integrated_docs_reduced_pending_when_marker_absent(self):
        import base64
        gh = mock.Mock()
        gh.api.return_value = '"' + base64.b64encode(b"name: CI\non:\n  push: {}\n").decode() + '"'
        result = converge_callers.check_integrated_docs_live(gh)
        self.assertEqual(result.status, "reduced-pending-Task-4-01")

    def test_integrated_docs_established_when_marker_present(self):
        import base64
        gh = mock.Mock()
        content = b"name: CI\non:\n  workflow_call:\n    inputs:\n      integrated-docs:\n        type: boolean\n"
        gh.api.return_value = '"' + base64.b64encode(content).decode() + '"'
        result = converge_callers.check_integrated_docs_live(gh)
        self.assertEqual(result.status, "established")

    def test_rulesets_reduced_pending_when_matrix_context_not_yet_required(self):
        """Corrected predicate (coordinator, 2026-08-04): the migration-window
        TARGET shape is `ci / matrix / ci-ok` present as a required context —
        both-present with `ci / ci-ok` satisfies it. A sample carrying ONLY
        the pre-existing `ci / ci-ok` (matrix context not yet required) is
        the reduced-pending / pre-convergence state."""
        gh = mock.Mock()
        gh.api.side_effect = [
            [{"id": 1}],
            {"rules": [{"type": "required_status_checks",
                        "parameters": {"required_status_checks": [{"context": "ci / ci-ok"}]}}]},
        ]
        result = converge_callers.check_rulesets_on_target(gh, sample_repos=["swift-primitives/swift-example"])
        self.assertEqual(result.status, "reduced-pending-Task-3-02")

    def test_rulesets_established_when_matrix_context_is_required(self):
        """Positive control for the corrected predicate: both `ci / ci-ok`
        AND `ci / matrix / ci-ok` required is the ESTABLISHED shape, not a
        transitional one — single-context exclusivity is a later predicate
        this function does not attempt to detect."""
        gh = mock.Mock()
        gh.api.side_effect = [
            [{"id": 1}],
            {"rules": [{"type": "required_status_checks",
                        "parameters": {"required_status_checks": [{"context": "ci / ci-ok"}, {"context": "ci / matrix / ci-ok"}]}}]},
        ]
        result = converge_callers.check_rulesets_on_target(gh, sample_repos=["swift-primitives/swift-example"])
        self.assertEqual(result.status, "established")

    def test_rulesets_established_even_when_matrix_context_is_the_only_one(self):
        """Negative control against re-introducing exclusivity: a sample
        carrying ONLY `ci / matrix / ci-ok` (the later, fully-converged
        shape) must still read as established by THIS predicate — it must
        never regress to reduced-pending once the fleet moves past
        both-present, which single-context-exclusivity coding would do."""
        gh = mock.Mock()
        gh.api.side_effect = [
            [{"id": 1}],
            {"rules": [{"type": "required_status_checks",
                        "parameters": {"required_status_checks": [{"context": "ci / matrix / ci-ok"}]}}]},
        ]
        result = converge_callers.check_rulesets_on_target(gh, sample_repos=["swift-primitives/swift-example"])
        self.assertEqual(result.status, "established")

    def test_rulesets_unmeasured_on_read_failure_never_silently_established(self):
        gh = mock.Mock()
        gh.api.side_effect = converge_callers.GhCallFailed("no access")
        result = converge_callers.check_rulesets_on_target(gh, sample_repos=["private-org/private-repo"])
        self.assertEqual(result.status, "unmeasured")


class ChecksReadyAndGreenTests(unittest.TestCase):
    """R6 Trap A/B, exercised directly against the predicate function."""

    def test_stale_head_run_does_not_block_or_satisfy(self):
        gh = mock.Mock()
        gh.api.return_value = {
            "check_runs": [
                {"name": "ci-ok", "head_sha": "OLDSHA", "status": "in_progress", "conclusion": None},
            ]
        }
        ready, ok, detail = converge_callers._checks_ready_and_green(gh, "o/r", "NEWSHA")
        self.assertTrue(ready)  # nothing AT the current head, so nothing pending
        self.assertTrue(ok)  # vacuously — no current-head runs to fail

    def test_non_terminal_current_head_run_is_not_ready(self):
        gh = mock.Mock()
        gh.api.return_value = {
            "check_runs": [{"name": "ci-ok", "head_sha": "NEWSHA", "status": "in_progress", "conclusion": None}]
        }
        ready, ok, detail = converge_callers._checks_ready_and_green(gh, "o/r", "NEWSHA")
        self.assertFalse(ready)

    def test_skipped_is_terminal_but_not_success(self):
        """Trap B, named explicitly."""
        gh = mock.Mock()
        gh.api.return_value = {
            "check_runs": [{"name": "ci-ok", "head_sha": "NEWSHA", "status": "completed", "conclusion": "skipped"}]
        }
        ready, ok, detail = converge_callers._checks_ready_and_green(gh, "o/r", "NEWSHA")
        self.assertTrue(ready)
        self.assertFalse(ok)
        self.assertIn("skipped", str(detail) + "")

    def test_all_success_at_current_head_is_ready_and_ok(self):
        gh = mock.Mock()
        gh.api.return_value = {
            "check_runs": [
                {"name": "ci-ok", "head_sha": "NEWSHA", "status": "completed", "conclusion": "success"},
                {"name": "lint", "head_sha": "NEWSHA", "status": "completed", "conclusion": "success"},
            ]
        }
        ready, ok, _ = converge_callers._checks_ready_and_green(gh, "o/r", "NEWSHA")
        self.assertTrue(ready)
        self.assertTrue(ok)


class RateLimitedGhTests(unittest.TestCase):
    def test_secondary_rate_limit_response_is_retried_not_raised(self):
        gh = converge_callers.RateLimitedGh()
        calls = []

        def fake_run(cmd, capture_output, text, timeout):
            calls.append(cmd)
            proc = mock.Mock()
            if len(calls) == 1:
                proc.returncode = 1
                proc.stderr = "You have exceeded a secondary rate limit"
                proc.stdout = ""
            else:
                proc.returncode = 0
                proc.stdout = "{}"
                proc.stderr = ""
            return proc

        with mock.patch("time.sleep", return_value=None), \
             mock.patch.object(subprocess, "run", side_effect=fake_run):
            out = gh.api("repos/foo/bar")
        self.assertEqual(out, {})
        self.assertEqual(len(calls), 2)

    def test_transient_502_is_retried_not_raised(self):
        """Positive control added after this task's own live census run
        hit a real `gh: HTTP 502` on an otherwise well-formed GraphQL call
        against the first organization queried — a transient infrastructure
        failure, not a quota signal, but equally not a reason to abandon a
        fleet-scale run partway through."""
        gh = converge_callers.RateLimitedGh()
        calls = []

        def fake_run(cmd, capture_output, text, timeout):
            calls.append(cmd)
            proc = mock.Mock()
            if len(calls) == 1:
                proc.returncode = 1
                proc.stderr = "gh: HTTP 502"
                proc.stdout = ""
            else:
                proc.returncode = 0
                proc.stdout = "{}"
                proc.stderr = ""
            return proc

        with mock.patch("time.sleep", return_value=None), \
             mock.patch.object(subprocess, "run", side_effect=fake_run):
            out = gh.api("repos/foo/bar")
        self.assertEqual(out, {})
        self.assertEqual(len(calls), 2)

    def test_ordinary_failure_is_not_retried_into_a_false_success(self):
        """Negative control: the retry path above is not simply masking
        every failure — an ordinary (non-secondary-rate-limit) error must
        still raise, on the first attempt."""
        gh = converge_callers.RateLimitedGh()

        def fake_run(cmd, capture_output, text, timeout):
            proc = mock.Mock()
            proc.returncode = 1
            proc.stderr = "404 Not Found"
            proc.stdout = ""
            return proc

        with mock.patch.object(subprocess, "run", side_effect=fake_run):
            with self.assertRaises(converge_callers.GhCallFailed):
                gh.api("repos/foo/bar")

    def test_checkpoint_sleeps_only_when_below_floor(self):
        gh = converge_callers.RateLimitedGh()

        def fake_run(cmd, capture_output, text, timeout):
            proc = mock.Mock()
            proc.returncode = 0
            proc.stdout = (
                '{"resources": {"core": {"remaining": 5000, "reset": 9999999999}, '
                '"graphql": {"remaining": 5000, "reset": 9999999999}}}'
            )
            proc.stderr = ""
            return proc

        with mock.patch("time.sleep") as sleep_mock, \
             mock.patch.object(subprocess, "run", side_effect=fake_run):
            gh.checkpoint()
        sleep_mock.assert_not_called()

    def test_checkpoint_sleeps_when_below_floor(self):
        """Positive control for the pacing mechanism itself: a genuinely
        low remaining count must actually trigger a sleep, not just be
        logged."""
        gh = converge_callers.RateLimitedGh()
        import time as time_module

        def fake_run(cmd, capture_output, text, timeout):
            proc = mock.Mock()
            proc.returncode = 0
            proc.stdout = (
                '{"resources": {"core": {"remaining": 10, "reset": %d}, '
                '"graphql": {"remaining": 10, "reset": %d}}}'
            ) % (int(time_module.time()) + 5, int(time_module.time()) + 5)
            proc.stderr = ""
            return proc

        with mock.patch("time.sleep") as sleep_mock, \
             mock.patch.object(subprocess, "run", side_effect=fake_run):
            gh.checkpoint()
        sleep_mock.assert_called_once()


class RollbackPersistenceTests(unittest.TestCase):
    def test_rollback_blob_is_written_under_the_receipts_directory(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            receipts = Path(tmp)
            out = converge_callers.persist_rollback_blob(
                receipts, "swift-primitives/swift-example",
                {"repository": "swift-primitives/swift-example", "base_sha": "a" * 40},
            )
            self.assertTrue(out.is_file())
            self.assertEqual(out.parent, receipts / "rollback")
            self.assertIn("swift-primitives__swift-example", out.name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
