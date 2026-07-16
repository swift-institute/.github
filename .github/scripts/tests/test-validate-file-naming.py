#!/usr/bin/env python3

from __future__ import annotations

from contextlib import redirect_stdout
import importlib.util
from io import StringIO
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "validate-file-naming.py"
SPEC = importlib.util.spec_from_file_location("validate_file_naming", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DiagnosticPrecedenceTests(unittest.TestCase):
    def validate(self, filename: str, source: str) -> list[str]:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            module_root = root / "Sources" / "Fixture Module"
            module_root.mkdir(parents=True)
            (module_root / filename).write_text(source, encoding="utf-8")
            output = StringIO()
            with redirect_stdout(output):
                module.validate_file_naming("swift-institute-test/fixture", root)
        return output.getvalue().splitlines()

    def test_where_root_suppresses_only_redundant_api_impl_006(self) -> None:
        lines = self.validate(
            "ValueConvertible.swift",
            """
public extension Namespace.Value where Element: Swift.Sequence {
    static var evidence: String { "extension Fake.Value where T: P" }
    // extension Comment.Value where T: P { }
}
""",
        )
        self.assertEqual(sum("\tAPI-IMPL-006\t" in line for line in lines), 0)
        self.assertEqual(sum("\tAPI-IMPL-007\t" in line for line in lines), 1)

    def test_member_only_api_impl_006_survives_high_frequency(self) -> None:
        source = "extension EnvVars { var value: String { \"value\" } }\n"
        for _ in range(1_000):
            self.assertFalse(
                module.api_impl_007_remediation_supersedes_api_impl_006(source)
            )
        lines = self.validate("EnvironmentVariables.swift", source)
        self.assertEqual(sum("\tAPI-IMPL-006\t" in line for line in lines), 1)

    def test_mixed_causes_retain_both_diagnostics(self) -> None:
        lines = self.validate(
            "QueryHelpers.swift",
            """
extension QueryExpression where QueryValue == String { }
extension SQLQueryExpression { }
""",
        )
        self.assertEqual(sum("\tAPI-IMPL-006\t" in line for line in lines), 1)
        self.assertEqual(sum("\tAPI-IMPL-007\t" in line for line in lines), 1)

    def test_nested_conformance_target_proves_precedence(self) -> None:
        source = "public extension Namespace.Value: Swift.Sequence { }\n"
        self.assertTrue(
            module.api_impl_007_remediation_supersedes_api_impl_006(source)
        )
        extension = module.top_level_extension_discriminators(source)[0]
        self.assertEqual(extension["target"], "Namespace.Value")
        self.assertTrue(extension["adds_conformance"])

    def test_comments_strings_and_attributes_do_not_invent_proof(self) -> None:
        source = """
// extension Comment.Value: Protocol { }
let text = "extension String.Value where T: P { }"
@available(macOS 15, *)
public extension Namespace.Value where Element: Swift.Sequence { }
"""
        extensions = module.top_level_extension_discriminators(source)
        self.assertEqual(len(extensions), 1)
        self.assertEqual(module.top_level_extension_keyword_count(source), 1)
        self.assertEqual(extensions[0]["target"], "Namespace.Value")
        # The existing pure-extension classifier cannot prove this annotated
        # shape, so precedence remains conservative and API-IMPL-006 stays.
        self.assertFalse(
            module.api_impl_007_remediation_supersedes_api_impl_006(source)
        )

    def test_specification_mirroring_basename_is_not_api_impl_006_candidate(self) -> None:
        self.assertFalse(module.is_compound_basename("RFC_4122"))


if __name__ == "__main__":
    unittest.main()
