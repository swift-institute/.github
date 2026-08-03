#!/usr/bin/env python3
"""validate-swiftlint-bitpattern-comment.py — verify the #218 fix to the
canonical `no_int_bitpattern_arithmetic` custom SwiftLint rule.

swift-institute/.github#218 (swift-tensors witness): the rule's regex ended
with `\\s*[+\\-*/]`, and `\\s*` spans newlines. An `Int(bitPattern:)` call
that ends a statement, followed by a blank line and a `//` or `/*` comment
(same line or on a following line), matched the comment's opening `/` as
division — a false positive with no arithmetic present. The fix narrows the
trailing whitespace to intra-line only (`[ \\t]*`) and excludes a `/`
immediately followed by `/` or `*` from the division alternative. Genuine
arithmetic — including true division — on an `Int(bitPattern:)` call site
must still fire.

Unlike the other `validate-*.py` scripts in this directory, this is not a
policy scan over an arbitrary target repository — every fixture is
synthetic and the "target" is always the SAME canonical `.swiftlint.yml`
this repository ships (`<repo_root>/.swiftlint.yml`, resolved from this
script's own location, not from the fixture's `repo_root` argument, which
only supplies the `Sources/` tree to lint). Detection is literal: shell out
to the real `swiftlint` binary — the only faithful arbiter of ICU/
NSRegularExpression regex behavior a Python reimplementation could silently
drift from — against every `*.swift` file under the fixture's `Sources/`
tree, and report any `no_int_bitpattern_arithmetic` finding.

`Package.swift` is deliberately excluded from the scan: it also carries a
`.swift` extension but is package metadata, not the fixture's Swift source
under test.

Files are passed to `swiftlint lint` individually rather than as a
directory: the canonical config's `included: [Sources, Tests]` is resolved
relative to the CONFIG's own directory, not the CLI-supplied path, so
scanning a fixture directory (which is not checked out at the config's own
`Sources/`) silently reports zero lintable files. Explicit file arguments
bypass that `included:` resolution and are linted directly.
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
from pathlib import Path

from validate_lib import emit

RELEVANT_RULE_ID = "no_int_bitpattern_arithmetic"
FINDING_PREFIX = "SWIFTLINT-BITPATTERN-COMMENT"


def canonical_config_path() -> Path:
    """Return <repo_root>/.swiftlint.yml for the checkout this script lives in.

    This script is at <repo_root>/.github/scripts/validate-swiftlint-
    bitpattern-comment.py; the canonical Tier 1 config under test is always
    the real <repo_root>/.swiftlint.yml, never a per-fixture file (the
    fixtures under test carry no `.swiftlint.yml` of their own — they exist
    only to be linted against the canonical one).
    """
    return Path(__file__).resolve().parents[2] / ".swiftlint.yml"


def lint_file(swiftlint: str, config: Path, swift_file: Path) -> list[dict]:
    result = subprocess.run(
        [swiftlint, "lint", "--config", str(config), "--reporter", "json", str(swift_file)],
        capture_output=True,
        text=True,
    )
    # swiftlint exits nonzero whenever it reports a finding at warning
    # severity or above -- expected for fail/ fixtures -- so a nonzero
    # returncode is not itself an error; only unparseable stdout is.
    try:
        return json.loads(result.stdout or "[]")
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"swiftlint output not valid JSON for {swift_file}: {e}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        ) from e


def main(repo: str, repo_root: str) -> int:
    swiftlint = shutil.which("swiftlint")
    if swiftlint is None:
        print("# error: swiftlint not installed", file=sys.stderr)
        return 2

    config = canonical_config_path()
    if not config.is_file():
        print(f"# error: canonical .swiftlint.yml not found at {config}", file=sys.stderr)
        return 2

    sources = Path(repo_root) / "Sources"
    if not sources.is_dir():
        return 0  # Fixture repo has nothing to lint under this rule.

    findings = 0
    for swift_file in sorted(sources.rglob("*.swift")):
        try:
            file_findings = lint_file(swiftlint, config, swift_file)
        except RuntimeError as e:
            print(f"# error: {e}", file=sys.stderr)
            return 2
        for finding in file_findings:
            rule_id = finding.get("rule_id")
            if rule_id == RELEVANT_RULE_ID:
                emit(
                    repo,
                    FINDING_PREFIX,
                    f"{rule_id} fired at {swift_file.name}:{finding.get('line')} "
                    f"({finding.get('reason', '')})",
                )
                findings += 1
    return findings


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: validate-swiftlint-bitpattern-comment.py <owner/name> <repo_root>")
    main(sys.argv[1], sys.argv[2])
