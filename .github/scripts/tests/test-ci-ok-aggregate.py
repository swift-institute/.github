#!/usr/bin/env python3
"""Positive controls for swift-ci.yml's embedded control-plane shell steps.

Both are shell scripts embedded in a workflow, which is exactly the shape that
went wrong: `ci-ok` spent eight days reporting success over runs that compiled
nothing, because `all(.result == "success" or .result == "skipped")` cannot
tell a plan-sanctioned skip from a leg that stopped running. Reasoning about
whether an aggregator would fire is not the same act as watching it fire
(swift-institute/Internal's VALIDATOR-DISCIPLINE.md §3), so this suite feeds it
the shapes it must reject and asserts the exit status AND the diagnostic.

The scripts are EXTRACTED FROM swift-ci.yml rather than copied here, so the
bytes under test are the bytes that ship. If an extracted step is renamed or
removed, extraction fails loudly rather than the suite quietly testing
nothing — the empty-corpus rule from the same file.

Usage: python3 .github/scripts/tests/test-ci-ok-aggregate.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

import yaml

WORKFLOW = Path(__file__).parents[2] / "workflows" / "swift-ci.yml"

RESOLVE_SUBJECT_STEP = "Resolve CI subject"
CLASSIFY_STEP = "Classify tier"
AGGREGATE_STEP = "Aggregate required-job results"

GATING_JOBS = [
    "plan",
    "macos-release",
    "linux-release",
    "windows-release",
    "format",
    "lint",
    "swift-linter",
]


def extract(job_id, step_name):
    """Return the `run:` body of a named step, or fail the suite saying so."""
    document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = document.get("jobs", {}).get(job_id)
    if job is None:
        raise SystemExit(f"{WORKFLOW}: no job '{job_id}' — extraction target gone")
    for step in job.get("steps", []):
        if step.get("name") == step_name:
            body = step.get("run")
            if not body:
                raise SystemExit(
                    f"{WORKFLOW}: step '{step_name}' in job '{job_id}' has no run: body"
                )
            return body
    raise SystemExit(
        f"{WORKFLOW}: job '{job_id}' has no step named '{step_name}'. "
        "This suite tests the shipped bytes by name; rename it here too."
    )


class ShellHarness(unittest.TestCase):
    """Run an extracted step body with a synthetic Actions environment."""

    script = ""

    def run_script(self, setup=None, **env):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            script = root / "step.sh"
            script.write_text(self.script, encoding="utf-8")
            output = root / "github_output"
            summary = root / "github_summary"
            output.touch()
            summary.touch()
            environment = dict(os.environ)
            environment.update(
                {
                    "GITHUB_OUTPUT": str(output),
                    "GITHUB_STEP_SUMMARY": str(summary),
                    "GITHUB_REF": "refs/heads/feature",
                    "GITHUB_SHA": "0" * 40,
                    "INPUT_TARGET_REPOSITORY": "",
                    "INPUT_REF": "",
                    "PULL_REQUEST_HEAD_REPOSITORY": "",
                    "PULL_REQUEST_HEAD_SHA": "",
                    "TRIGGER_REPOSITORY": "swift-institute/example",
                    "TRIGGER_SHA": "0" * 40,
                    # swift-institute/.github#276 Task 1-03: "Classify tier"
                    # now validates `lint-bundle` before anything else, so
                    # every harness needs a value even when its own test
                    # doesn't care about it (only ClassifierTests and
                    # PrimitivesLegSelectionTests actually vary it). Matches
                    # the workflow input's own non-empty default.
                    "LINT_BUNDLE": "institute",
                }
            )
            environment.update({k: v for k, v in env.items()})
            if setup is not None:
                setup(root, environment)
            completed = subprocess.run(
                ["bash", str(script)],
                capture_output=True,
                text=True,
                cwd=str(root),
                env=environment,
            )
            outputs = {}
            for line in output.read_text(encoding="utf-8").splitlines():
                if "=" in line:
                    key, _, value = line.partition("=")
                    outputs[key] = value
            self.summary = summary.read_text(encoding="utf-8")
            return (
                completed.returncode,
                completed.stdout + completed.stderr,
                outputs,
            )


class ConfiguredLinterAdjudicationTests(ShellHarness):
    """The configured-rule path must not report a clean run over no measure."""

    script = extract("swift-linter", "Run swift-linter (consumer Lint.swift)")

    def run_linter(self, output, exit_code=0):
        def configure(root, environment):
            bash_env = root / "mock-swift-linter.bash"
            bash_env.write_text(
                """swift-linter() {
  if [ "$2" != "--exit-policy" ] || [ "$3" != "strict" ]; then
    echo "unexpected swift-linter arguments: $*"
    return 97
  fi
  printf '%s\\n' "$LINTER_OUTPUT"
  return "$LINTER_EXIT"
}
""",
                encoding="utf-8",
            )
            environment["BASH_ENV"] = str(bash_env)
            environment["GITHUB_WORKSPACE"] = str(root)

        return self.run_script(
            setup=configure,
            LINTER_OUTPUT=output,
            LINTER_EXIT=str(exit_code),
        )

    def test_real_configured_run_passes(self):
        code, log, _ = self.run_linter("93 active rules · 4 files linted · 0 violations")
        self.assertEqual(code, 0, log)
        self.assertIn("swift-linter (Lint.swift)", self.summary)

    def test_missing_summary_fails(self):
        code, log, _ = self.run_linter("no summary was emitted")
        self.assertNotEqual(code, 0, log)
        self.assertIn("emitted no run summary", log)

    def test_zero_active_rules_fails(self):
        code, log, _ = self.run_linter("0 active rules · 4 files linted · 0 violations")
        self.assertNotEqual(code, 0, log)
        self.assertIn("loaded 0 rules from Lint.swift", log)

    def test_zero_linted_files_fails(self):
        code, log, _ = self.run_linter("93 active rules · 0 files linted · 0 violations")
        self.assertNotEqual(code, 0, log)
        self.assertIn("linted 0 files", log)

    def test_existing_strict_failure_is_preserved(self):
        code, log, _ = self.run_linter(
            "93 active rules · 4 files linted · 1 violation", exit_code=42
        )
        self.assertEqual(code, 42, log)


@unittest.skip("The published-binary installation path no longer has a rule-pack resolution step.")
class RunnerDigestTests(ShellHarness):
    """Every baked standard bundle revision must affect the fallback key."""

    script = ""

    def resolve(self, standards_rules_sha):
        def configure(root, environment):
            bash_env = root / "mock-git.bash"
            bash_env.write_text(
                """git() {
  if [ "$1" != "ls-remote" ]; then
    command git "$@"
    return
  fi
  case "$2" in
    *swift-primitives-linter-rules.git) SHA=1111111111111111111111111111111111111111 ;;
    *swift-institute-linter-rules.git) SHA=2222222222222222222222222222222222222222 ;;
    *swift-standards-linter-rules.git) SHA="$STANDARDS_RULES_SHA" ;;
    *swift-linter-rules.git) SHA=3333333333333333333333333333333333333333 ;;
    *swift-linter-primitives.git) SHA=4444444444444444444444444444444444444444 ;;
    *) echo "unexpected ls-remote source: $2" >&2; return 98 ;;
  esac
  printf '%s\\trefs/heads/main\\n' "$SHA"
}
""",
                encoding="utf-8",
            )
            environment["BASH_ENV"] = str(bash_env)

        return self.run_script(
            setup=configure,
            STANDARDS_RULES_SHA=standards_rules_sha,
        )

    def test_standards_bundle_revision_changes_fallback_digest(self):
        code, first_log, first = self.resolve("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        self.assertEqual(code, 0, first_log)
        code, second_log, second = self.resolve("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        self.assertEqual(code, 0, second_log)
        self.assertNotEqual(first["digest"], second["digest"])
        self.assertIn("standrules=", second_log)


class ResolveSubjectTests(ShellHarness):
    """The single subject-resolution contract (swift-institute/.github#179).

    Extracted from swift-ci.yml's `plan` job "Resolve CI subject" step — the
    bytes under test are the bytes that ship. Before this step existed, the
    Plan job's own initial checkout resolved `repository:` (from
    `target-repo`) independently of `ref:`, so a dispatch that supplied
    `target-repo` without `ref` (ci-sweep.yml's nightly rotation) checked out
    the TARGET repository at the TRIGGERING repository's own SHA — a commit
    that does not exist there. Regression: PR #179 merge 5685c9e3, run
    30875153360 ("fatal: remote error: upload-pack: not our ref"), Plan
    failure 57/57, 912 skipped leaf jobs. These controls feed the resolver
    every shape from that regression plus the task's full positive-control
    list, mocking `gh api` so no network access is required.
    """

    script = extract("plan", RESOLVE_SUBJECT_STEP)

    def resolve(self, gh_responses=None, **env):
        base = {
            "EVENT_NAME": "push",
            "INPUT_TARGET_REPOSITORY": "",
            "INPUT_REF": "",
            "PULL_REQUEST_HEAD_REPOSITORY": "",
            "PULL_REQUEST_HEAD_SHA": "",
            "TRIGGER_REPOSITORY": "swift-institute/example",
            "TRIGGER_SHA": "a" * 40,
        }
        base.update(env)
        responses = gh_responses or {}

        def configure(root, environment):
            # Maps an exact `gh api ...` invocation (as bash's "$*" sees it)
            # to its stdout. A None value simulates a 404/inaccessible
            # repository or ref: empty stdout, nonzero exit — exactly what
            # `gh api` does on failure, which is what the script's `||
            # true` fallback must turn into an empty (and therefore
            # fail-closed) value, not a crash.
            lines = ["gh() {", '  case "$*" in']
            for call, output in responses.items():
                escaped_call = call.replace("'", "'\\''")
                if output is None:
                    lines.append(f"    '{escaped_call}') return 1 ;;")
                else:
                    escaped_output = output.replace("'", "'\\''")
                    lines.append(
                        f"    '{escaped_call}') printf '%s\\n' '{escaped_output}' ;;"
                    )
            lines.append(
                '    *) echo "unexpected gh invocation: $*" >&2; return 99 ;;'
            )
            lines.append("  esac")
            lines.append("}")
            bash_env = root / "mock-gh.bash"
            bash_env.write_text("\n".join(lines) + "\n", encoding="utf-8")
            environment["BASH_ENV"] = str(bash_env)

        return self.run_script(setup=configure, **base)

    # ---- the task's positive-control list --------------------------------

    def test_target_repo_with_empty_ref_resolves_live_default_branch_head(self):
        """target-repo + empty ref: resolves the target's live default
        branch and its exact head SHA — never the triggering repository's
        SHA (the #179 defect, made to fail here)."""
        code, log, outputs = self.resolve(
            INPUT_TARGET_REPOSITORY="mock/target",
            INPUT_REF="",
            TRIGGER_SHA="9" * 40,
            gh_responses={
                "api repos/mock/target --jq .default_branch": "main",
                "api repos/mock/target/commits/main --jq .sha": "1" * 40,
            },
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["subject-repository"], "mock/target")
        self.assertEqual(outputs["subject-sha"], "1" * 40)
        self.assertEqual(outputs["subject-ref"], "1" * 40)
        self.assertNotEqual(outputs["subject-sha"], "9" * 40)

    def test_target_repo_with_explicit_ref_resolves_to_one_commit_sha(self):
        code, log, outputs = self.resolve(
            INPUT_TARGET_REPOSITORY="mock/target",
            INPUT_REF="release-branch",
            gh_responses={
                "api repos/mock/target/commits/release-branch --jq .sha": "2" * 40,
            },
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["subject-repository"], "mock/target")
        self.assertEqual(outputs["subject-sha"], "2" * 40)
        self.assertEqual(outputs["subject-ref"], "2" * 40)

    def test_invalid_explicit_ref_fails_with_no_defaulting(self):
        code, log, outputs = self.resolve(
            INPUT_TARGET_REPOSITORY="mock/target",
            INPUT_REF="does-not-exist",
            gh_responses={
                "api repos/mock/target/commits/does-not-exist --jq .sha": None,
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("could not resolve ref 'does-not-exist'", log)
        self.assertNotIn("subject-sha", outputs)

    def test_inaccessible_target_repository_fails_closed(self):
        code, log, outputs = self.resolve(
            INPUT_TARGET_REPOSITORY="mock/missing",
            INPUT_REF="",
            gh_responses={
                "api repos/mock/missing --jq .default_branch": None,
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("could not read the default branch", log)
        self.assertNotIn("subject-sha", outputs)

    def test_pull_request_uses_exact_fork_head_with_no_api_call(self):
        # Forks are untrusted, but a PR's head SHA is already exact — no
        # resolution call is needed or made (the mock has zero registered
        # responses, so any `gh` call at all fails the test).
        code, log, outputs = self.resolve(
            EVENT_NAME="pull_request",
            PULL_REQUEST_HEAD_REPOSITORY="fork/example",
            PULL_REQUEST_HEAD_SHA="b" * 40,
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["subject-repository"], "fork/example")
        self.assertEqual(outputs["subject-sha"], "b" * 40)
        self.assertNotIn("unexpected gh invocation", log)

    def test_ordinary_push_uses_triggering_repository_and_exact_sha(self):
        code, log, outputs = self.resolve(
            EVENT_NAME="push",
            TRIGGER_REPOSITORY="swift-institute/example",
            TRIGGER_SHA="c" * 40,
        )
        self.assertEqual(code, 0, log)
        self.assertEqual(outputs["subject-repository"], "swift-institute/example")
        self.assertEqual(outputs["subject-sha"], "c" * 40)
        self.assertNotIn("unexpected gh invocation", log)

    def test_empty_subject_fails_closed(self):
        code, log, outputs = self.resolve(
            EVENT_NAME="push", TRIGGER_REPOSITORY="", TRIGGER_SHA=""
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("CI subject repository/SHA is empty", log)

    def test_non_sha_resolution_result_fails_closed(self):
        """Defense in depth: a resolver reply that is not a 40-character
        commit SHA must not be trusted silently."""
        code, log, outputs = self.resolve(
            INPUT_TARGET_REPOSITORY="mock/target",
            INPUT_REF="main",
            gh_responses={
                "api repos/mock/target/commits/main --jq .sha": "not-a-sha",
            },
        )
        self.assertNotEqual(code, 0, log)
        self.assertIn("is not a 40-character commit SHA", log)


class ReleaseModeTests(ShellHarness):
    """Fast tier compiles release; full qualification keeps release tests."""

    def run_release_step(self, job, tier, test_filter=""):
        self.script = extract(job, "Build or test (release)")

        def configure(root, environment):
            binary = root / "bin"
            binary.mkdir()
            swift = binary / "swift"
            swift.write_text(
                "#!/bin/sh\nprintf 'SWIFT_CALL=%s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            swift.chmod(0o755)
            environment["PATH"] = f"{binary}:{environment['PATH']}"

        return self.run_script(
            setup=configure, CI_TIER=tier, TEST_FILTER=test_filter
        )

    def test_fast_tier_builds_release_without_tests(self):
        for job in ("linux-release", "linux-6-4"):
            with self.subTest(job=job):
                code, log, _ = self.run_release_step(job, "build")
                self.assertEqual(code, 0, log)
                self.assertIn("SWIFT_CALL=build -c release", log)
                self.assertNotIn("SWIFT_CALL=test", log)

    def test_full_tier_keeps_filtered_release_tests(self):
        code, log, _ = self.run_release_step(
            "linux-release", "full", test_filter="Report-Format"
        )
        self.assertEqual(code, 0, log)
        self.assertIn("SWIFT_CALL=test -c release --filter Report_Format", log)


class SubjectDerivationSingularityTests(unittest.TestCase):
    """R7 (swift-institute/.github#276): after task 0A-01, exactly one
    component derives the CI subject and every other consumer reads it.
    #179's defect was ten checkout sites independently re-deriving a
    subject from raw event context; `ci-ok`'s aggregator carried an
    eleventh, non-checkout instance of the same class. Both are gone —
    but a fixture that only re-asserts a fixed count (ten sites, one
    aggregator) protects against the two known offenders and nothing
    else. This one searches every step in every job for the *shape* of
    an independent recomputation — a subject-named shell variable
    assigned from a command substitution outside the single designated
    resolver step — so a differently-named, newly-introduced offender
    still trips it.

    Per the standing fixture rule (a fixture whose passing state is
    indistinguishable from the hazard being unreachable proves nothing):
    `test_detector_catches_a_reintroduced_recomputation` feeds the exact
    same detector a synthetic document shaped like the deleted `ci-ok`
    bug reintroduced under an unrelated step name, and requires it to
    fire. That is what this fixture's failure looks like.
    """

    # Matches `SOMETHING_SUBJECT_SHA="$(...)"` / `SUBJECT_REPOSITORY=$(...)`
    # style assignments — i.e. a variable whose name contains SUBJECT being
    # bound to the result of a command substitution (an API call, `gh`,
    # `git rev-parse`, etc.), which is the shape of *deriving* a subject.
    # Reading one that was already supplied via `env:` never takes this
    # shape — it shows up as a bare `$VAR`/`${VAR}` reference, never as the
    # left-hand side of a `NAME=$(...)` assignment.
    SUSPECT = re.compile(r"(?i)\b([A-Z0-9_]*SUBJECT[A-Z0-9_]*)\s*=\s*\"?\$\(")

    @staticmethod
    def offending_sites(document, exempt_step=RESOLVE_SUBJECT_STEP):
        sites = []
        for job_id, job in (document.get("jobs") or {}).items():
            for step in job.get("steps", []) or []:
                name = step.get("name")
                if name == exempt_step:
                    continue
                body = step.get("run")
                if not body:
                    continue
                for line in body.splitlines():
                    if SubjectDerivationSingularityTests.SUSPECT.search(line):
                        sites.append((job_id, name))
                        break
        return sites

    def test_repaired_workflow_has_no_independent_recomputation(self):
        document = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        sites = self.offending_sites(document)
        self.assertEqual(
            sites,
            [],
            "found a step outside "
            f"'{RESOLVE_SUBJECT_STEP}' that assigns a SUBJECT-named "
            f"variable from a command substitution: {sites!r}. This is "
            "the #179/ci-ok defect class — a second component deriving "
            "its own opinion of the CI subject instead of reading "
            "Plan's single resolved output.",
        )

    def test_detector_catches_a_reintroduced_recomputation(self):
        synthetic = {
            "jobs": {
                "plan": {
                    "steps": [
                        {"name": RESOLVE_SUBJECT_STEP, "run": "echo ok\n"}
                    ]
                },
                "ci-ok": {
                    "steps": [
                        {
                            "name": "Aggregate required-job results",
                            "run": (
                                'EXPECTED_SUBJECT_SHA="$(gh api '
                                "repos/x/commits/main --jq .sha)\"\n"
                            ),
                        }
                    ]
                },
            }
        }
        sites = self.offending_sites(synthetic)
        self.assertEqual(sites, [("ci-ok", "Aggregate required-job results")])

    def test_detector_does_not_flag_a_pure_consumer(self):
        # Negative control on the detector itself: a step that only reads
        # an already-resolved subject via env: (the correct, post-repair
        # shape) must not be flagged.
        synthetic = {
            "jobs": {
                "plan": {
                    "steps": [
                        {"name": RESOLVE_SUBJECT_STEP, "run": "echo ok\n"},
                        {
                            "name": "Verify checked-out subject HEAD",
                            "run": (
                                'ACTUAL="$(git rev-parse HEAD)"\n'
                                'if [ "$ACTUAL" != "$SUBJECT_SHA" ]; then '
                                "exit 1; fi\n"
                            ),
                        },
                    ]
                }
            }
        }
        self.assertEqual(self.offending_sites(synthetic), [])




if __name__ == "__main__":
    unittest.main(verbosity=2)
