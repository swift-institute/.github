#!/usr/bin/env python3
"""
Tests for generate-caller.py (Task 5-01, swift-institute/.github#276, #282).

Two evidence classes:

  - RealCallerRoundTripTests runs `parse_existing_caller` against seven
    real `.github/workflows/ci.yml` files fetched live while building this
    generator (fixtures/callers/), across every caller shape sampled:
    same-org/cross-org x Primitives/Standards/Foundations, and the three
    known `platform-support` holders named in the programme's Task 0C-01
    positive control (`swift-linux-standard`, `swift-windows-32`,
    `swift-iso-9945`) — each must expose its known value, not merely
    parse without error.
  - GeneratorTests and UnknownCustomizationTests exercise every documented
    positive control from synthetic specs/documents: reordered-field
    determinism, same-org vs. cross-org secret shape, an unapproved
    `with:` key failing closed, inline `runs-on:`/`steps:` failing closed,
    and a fourth/unknown typed input being rejected rather than silently
    dropped.

Usage: python3 .github/scripts/tests/test-generate-caller.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).parent
SCRIPTS_DIR = TESTS_DIR.parent
FIXTURES_DIR = TESTS_DIR / "fixtures" / "callers"

# Dataclasses under this local Python's `_is_type` resolution need the
# module registered in sys.modules BEFORE exec — otherwise
# `sys.modules.get(cls.__module__)` returns None during class construction
# and dataclass field resolution raises. Normal `python3 script.py`
# execution never hits this (the module is the top-level __main__, always
# registered); it is purely an artifact of loading a hyphenated-filename
# module for testing, so it is handled once, here.
_spec = importlib.util.spec_from_file_location(
    "generate_caller", SCRIPTS_DIR / "generate-caller.py"
)
generate_caller = importlib.util.module_from_spec(_spec)
sys.modules["generate_caller"] = generate_caller
_spec.loader.exec_module(generate_caller)

CallerSpec = generate_caller.CallerSpec
generate = generate_caller.generate
parse_existing_caller = generate_caller.parse_existing_caller
UnknownCustomization = generate_caller.UnknownCustomization


class RealCallerRoundTripTests(unittest.TestCase):
    """The task's own positive control: 'the three known platform-support
    callers round-trip byte/semantically without losing values.' Extended
    here to all seven sampled callers, same-org and cross-org, across all
    three layers.
    """

    CASES = [
        ("array-primitives.yml", "swift-primitives/swift-array-primitives", "primitives", True, None),
        ("domain-standard.yml", "swift-standards/swift-domain-standard", "standards", True, None),
        ("copy-on-write.yml", "swift-foundations/swift-copy-on-write", "institute", True, None),
        ("rfc-3986.yml", "swift-ietf/swift-rfc-3986", "standards", False, None),
        ("linux-standard.yml", "swift-linux-foundation/swift-linux-standard", "standards", False, "apple,linux"),
        ("windows-32.yml", "swift-microsoft/swift-windows-32", "standards", False, "windows"),
        ("iso-9945.yml", "swift-iso/swift-iso-9945", "standards", False, "apple,linux"),
    ]

    def test_every_sampled_caller_parses_with_the_expected_shape(self):
        for filename, repository, layer, expected_same_org, expected_platform in self.CASES:
            with self.subTest(repository=repository):
                text = (FIXTURES_DIR / filename).read_text(encoding="utf-8")
                spec = parse_existing_caller(text, repository, layer)
                self.assertEqual(spec.same_org, expected_same_org)
                self.assertEqual(spec.platform_support, expected_platform)

    def test_generated_output_from_the_recovered_spec_is_a_valid_caller(self):
        # Round-trip a second hop: recovered spec -> generate -> parse
        # again -> identical spec. Proves the generator's own output is
        # itself always re-parseable, not just that parsing succeeds once.
        for filename, repository, layer, _, _ in self.CASES:
            with self.subTest(repository=repository):
                original_text = (FIXTURES_DIR / filename).read_text(encoding="utf-8")
                spec = parse_existing_caller(original_text, repository, layer)
                regenerated_text = generate(spec)
                spec_again = parse_existing_caller(regenerated_text, repository, layer)
                self.assertEqual(spec, spec_again)


class GeneratorTests(unittest.TestCase):
    def test_reordered_construction_produces_byte_identical_output(self):
        """Positive control: 'reordered input produces byte-identical
        canonical YAML.'"""
        a = CallerSpec(
            repository="swift-primitives/swift-example",
            layer="primitives",
            platform_support="apple,linux",
            enable_private_repos=True,
        )
        b = CallerSpec(
            enable_private_repos=True,
            platform_support="apple,linux",
            layer="primitives",
            repository="swift-primitives/swift-example",
        )
        self.assertEqual(generate(a), generate(b))

    def test_same_org_emits_secrets_inherit_and_tag_trigger(self):
        spec = CallerSpec(repository="swift-primitives/swift-example", layer="primitives")
        text = generate(spec)
        self.assertIn("secrets: inherit", text)
        self.assertIn("tags:", text)
        self.assertIn("- '*'", text)
        # inherit appears exactly once (the single terminal ci: job), never
        # the four-name explicit block.
        self.assertEqual(text.count("secrets: inherit"), 1)
        for name in generate_caller.CI059_SECRET_NAMES:
            self.assertNotIn(name, text)

    def test_cross_org_emits_exactly_the_four_ci059_secrets_and_the_tag_trigger(self):
        # Terminal canonical contract (§5.1): tags trigger on EVERY
        # ordinary class, cross-org included.
        spec = CallerSpec(repository="swift-ietf/swift-example", layer="standards")
        text = generate(spec)
        self.assertNotIn("secrets: inherit", text)
        self.assertIn("tags:", text)
        for name in generate_caller.CI059_SECRET_NAMES:
            with self.subTest(name=name):
                # Twice in the single ci: job (the YAML key and the
                # `${{ secrets.NAME }}` expression value).
                self.assertEqual(text.count(name), 2)

    def test_detector_catches_a_caller_missing_the_tag_trigger(self):
        """Positive control: the tag-trigger assertion must be something
        the test can tell apart, not an assertion that happens to pass
        regardless."""
        spec = CallerSpec(repository="swift-primitives/swift-example", layer="primitives")
        text = generate(spec)
        neutered = text.replace("    tags:\n      - '*'\n", "")
        self.assertNotIn("tags:", neutered)
        self.assertNotEqual(text, neutered)

    def test_platform_support_is_preserved_by_exact_value(self):
        spec = CallerSpec(repository="swift-iso/swift-example", layer="standards", platform_support="apple,linux")
        text = generate(spec)
        self.assertIn("platform-support: apple,linux", text)

    def test_no_with_block_when_no_typed_input_is_set(self):
        # TX8: the bridge input is elided; a caller with no typed inputs
        # carries no with: block at all.
        spec = CallerSpec(repository="swift-standards/swift-example", layer="standards")
        text = generate(spec)
        self.assertNotIn("with:", text)
        self.assertNotIn("integrated-docs", text)

    def test_terminal_form_is_single_job_with_permissions_and_no_bridge_input(self):
        spec = CallerSpec(repository="swift-primitives/swift-example", layer="primitives")
        text = generate(spec)
        self.assertIn("  ci:", text)
        self.assertNotIn("  docs:", text)
        self.assertNotIn("swift-docs.yml", text)
        self.assertNotIn("integrated-docs", text)
        self.assertIn("permissions:\n  actions: read\n  contents: read\n", text)

    def test_bridge_input_in_an_existing_caller_parses_clean_and_is_elided(self):
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    with:
      integrated-docs: true
    secrets: inherit
"""
        spec = parse_existing_caller(text, "swift-primitives/swift-example", "primitives")
        self.assertNotIn("integrated-docs", generate(spec))

    def test_legacy_docs_job_with_overrides_maps_onto_docs_inputs(self):
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
  docs:
    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
    with:
      umbrella-module: Example
      exclude-modules: Internal
    secrets: inherit
"""
        spec = parse_existing_caller(text, "swift-primitives/swift-example", "primitives")
        self.assertEqual(spec.docs_umbrella_module, "Example")
        self.assertEqual(spec.docs_exclude_modules, "Internal")
        regenerated = generate(spec)
        self.assertIn("docs-umbrella-module: Example", regenerated)
        self.assertIn("docs-exclude-modules: Internal", regenerated)

    def test_invalid_layer_is_rejected_at_construction(self):
        with self.assertRaises(ValueError):
            CallerSpec(repository="swift-primitives/swift-example", layer="bogus")


class UnknownCustomizationTests(unittest.TestCase):
    """Change item 5: 'unknown input, local runs-on:, steps:, extra
    workflow, or bespoke logic is not erased; generation fails and routes
    it to typed exception/review.' Every hazard this generator must
    refuse rather than silently regenerate over, proven to actually be
    refused — not merely documented as refused.
    """

    def _parse(self, yaml_text: str):
        return parse_existing_caller(yaml_text, "swift-primitives/swift-example", "primitives")

    def test_an_unapproved_with_key_is_rejected(self):
        """Positive control: 'a synthetic fourth typed input is discovered
        and either preserved by approved schema or rejected; never
        erased.'"""
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    with:
      bogus-fourth-input: something
    secrets: inherit
  docs:
    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
    secrets: inherit
"""
        with self.assertRaises(UnknownCustomization) as ctx:
            self._parse(text)
        self.assertIn("bogus-fourth-input", str(ctx.exception))

    def test_inline_runs_on_is_rejected(self):
        """Positive control: 'unknown runs-on/step/bespoke workflow is
        rejected.'"""
        text = """\
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
  docs:
    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
    secrets: inherit
"""
        with self.assertRaises(UnknownCustomization):
            self._parse(text)

    def test_an_extra_job_is_rejected(self):
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
  docs:
    uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
    secrets: inherit
  extra-bespoke-job:
    runs-on: ubuntu-latest
    steps:
      - run: echo surprise
"""
        with self.assertRaises(UnknownCustomization):
            self._parse(text)

    def test_single_job_legacy_shape_without_bridge_input_parses_clean(self):
        # A caller already reduced to one ci: job (no separate docs) is
        # admissible for terminal regeneration; the bridge input is
        # generator-owned, so its absence in the input is not a defect.
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
"""
        spec = self._parse(text)
        self.assertEqual(spec.layer, "primitives")

    def test_cross_wrapper_docs_route_is_rejected(self):
        text = """\
jobs:
  ci:
    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
    secrets: inherit
  docs:
    uses: swift-standards/.github/.github/workflows/swift-docs.yml@main
    secrets: inherit
"""
        with self.assertRaises(UnknownCustomization):
            self._parse(text)

    def test_a_valid_caller_does_not_raise(self):
        """Negative control: the rejection tests above are not simply
        over-eager — a genuinely canonical caller passes clean."""
        text = generate(CallerSpec(repository="swift-primitives/swift-example", layer="primitives"))
        spec = self._parse(text)
        self.assertEqual(spec.layer, "primitives")


class CommandLineTests(unittest.TestCase):
    def test_generate_mode_round_trips_through_the_cli(self):
        import json
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            spec_path = Path(raw) / "spec.json"
            spec_path.write_text(
                json.dumps({"repository": "swift-primitives/swift-example", "layer": "primitives"}),
                encoding="utf-8",
            )
            completed = subprocess.run(
                [sys.executable, str(SCRIPTS_DIR / "generate-caller.py"), "generate", str(spec_path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("secrets: inherit", completed.stdout)

    def test_generate_then_parse_round_trips_through_the_cli_end_to_end(self):
        """The exact regression this test class exists to catch: an
        earlier draft's `parse` mode hardcoded a placeholder repository
        ("<cli>/<cli>"), which is never same-org with any real wrapper, so
        piping `generate`'s own output back into `parse` always produced a
        false UnknownCustomization — a same-org caller misclassified as
        cross-org purely by the CLI plumbing, not by the library logic
        the other tests in this file exercise directly. Caught by running
        the CLI as CI actually would (two real subprocess calls, not an
        in-process import), before shipping it."""
        import json
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            spec_path = Path(raw) / "spec.json"
            spec_path.write_text(
                json.dumps({"repository": "swift-primitives/swift-example", "layer": "primitives"}),
                encoding="utf-8",
            )
            caller_path = Path(raw) / "ci.yml"
            generated = subprocess.run(
                [sys.executable, str(SCRIPTS_DIR / "generate-caller.py"), "generate", str(spec_path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(generated.returncode, 0, generated.stderr)
            caller_path.write_text(generated.stdout, encoding="utf-8")

            parsed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS_DIR / "generate-caller.py"),
                    "parse",
                    str(caller_path),
                    "swift-primitives/swift-example",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            result = json.loads(parsed.stdout)
            self.assertEqual(result["layer"], "primitives")
            self.assertTrue(result["same_org"])

    def test_parse_mode_reports_unknown_customization_as_a_cli_error(self):
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            caller_path = Path(raw) / "ci.yml"
            caller_path.write_text(
                "jobs:\n  ci:\n    runs-on: ubuntu-latest\n    steps: []\n",
                encoding="utf-8",
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS_DIR / "generate-caller.py"),
                    "parse",
                    str(caller_path),
                    "swift-primitives/swift-example",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(completed.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
