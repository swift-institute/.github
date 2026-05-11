#!/usr/bin/env python3
"""validate-diagnostic-format.py — verify lint-rule diagnostic message format.

Wave 4 mechanization (2026-05-11) — companion to validate-diagnostic-format.yml.

Rule checked:
  [API-NAME-009] Diagnostic-emitting rules' message strings MUST follow the
                 educational-diagnostic format `[<rule_id>] <citation>:
                 <description>`. The citation is either a skill rule ID
                 (`[API-ERR-001]`), a feedback-memory filename
                 (`feedback_no_try_optional`), or a research-doc path
                 (`Research/typed-throws-rationale.md`). Mechanical narrow
                 check: a `static let message: String = "..."` declaration
                 in a `Lint.Rule.*.*.swift` source file whose literal string
                 does NOT begin with `[<rule_id>] <citation>:` is flagged.

Detection scope:
- `Sources/**/Lint.Rule.*.*.swift` — narrow to the institute's linter-rule
  authoring sites. Other Swift files (rule-runner infrastructure, output
  formatters, the rule registry itself) are out of scope.
- The rule does NOT verify the citation's existence — that's a research /
  skill-corpus concern. It verifies only the message-text shape per
  [API-NAME-009].
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

# Find: `static let message[: Swift.String]? = ` followed by one or more
# string literals chained with `+`. Capture the entire expression text so
# the format check can run against the concatenated content.
MESSAGE_DECL = re.compile(
    r"(?:@usableFromInline\s+|public\s+|internal\s+|fileprivate\s+|private\s+|package\s+|\s)*"
    r"static\s+let\s+message\s*(?::\s*[\w.]+)?\s*=\s*"
    r"((?:\s*\"(?:[^\"\\]|\\.)*\"\s*\+?)+)",
    re.MULTILINE,
)
STRING_LITERAL = re.compile(r"\"((?:[^\"\\]|\\.)*)\"")

# Expected format: leading `[<rule_id>] <citation>: ...`
# - rule_id: snake_case or kebab-case identifier in brackets
# - citation: a non-empty token sequence. Canonical forms (skill ID
#   `[API-ERR-001]`, `feedback_id`, `Research/path.md`) are the simple
#   cases; the codebase also chains them with `/` (e.g.,
#   `[PATTERN-005b]/[MEM-SAFE-002]`) and uses bare `<file>.md` paths.
# - then `: ` separating description.
# Mechanical narrow check: the leading rule-id bracket exists, a non-empty
# citation segment follows, and the citation ends with `:` plus whitespace.
FORMAT_RE = re.compile(
    r"^\["                                    # opening [
    r"[a-z_][\w-]*"                           # rule_id (snake_case or kebab-case)
    r"\]\s+"                                  # closing ] + space
    r"\S[^:]*?"                               # citation: non-empty, no colon
    r"\s*:\s"                                 # : separator
)


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def iter_lint_rule_sources(repo_root: Path):
    """Yield every Lint.Rule.{Module}.{Name}.swift file under Sources/.

    The convention per skill `[API-NAME-001]` is dotted basenames; rule
    source files specifically match the `Lint.Rule.*.*.swift` pattern. The
    namespace placeholder file `Lint.Rule.{Module}.swift` (no third
    segment) is excluded — it carries the namespace declaration, not a
    rule body.
    """
    sources = repo_root / "Sources"
    if not sources.is_dir():
        return
    for p in sources.rglob("Lint.Rule.*.*.swift"):
        # Need to filter the namespace shape `Lint.Rule.Foo.swift`
        # (3 dot-separated segments + .swift). A rule file has 4 segments
        # (e.g., `Lint.Rule.Foo.Bar.swift`).
        stem = p.stem
        if stem.count(".") < 3:
            continue
        relative = p.relative_to(repo_root)
        if any(seg.startswith(".") for seg in relative.parts):
            continue
        yield p


def check_message_format(text: str) -> list[str]:
    """Return a list of message strings that violate the format."""
    violations: list[str] = []
    for m in MESSAGE_DECL.finditer(text):
        expression = m.group(1)
        # Concatenate every string literal in the `+`-chain.
        concatenated_parts: list[str] = []
        for sm in STRING_LITERAL.finditer(expression):
            piece = sm.group(1)
            unescaped = (
                piece.replace("\\n", "\n")
                .replace("\\t", "\t")
                .replace('\\"', '"')
                .replace("\\\\", "\\")
            )
            concatenated_parts.append(unescaped)
        concatenated = "".join(concatenated_parts)
        if not FORMAT_RE.match(concatenated):
            preview = concatenated[:80].replace("\n", " ")
            violations.append(preview)
    return violations


def validate_diagnostic_format(repo: str, repo_root: Path) -> int:
    findings = 0
    for f in iter_lint_rule_sources(repo_root):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for preview in check_message_format(text):
            emit(repo, "API-NAME-009",
                 f"{f.relative_to(repo_root)}: `static let message` does "
                 f"not follow the educational-diagnostic format "
                 f"`[<rule_id>] <citation>: <description>` per "
                 f"[API-NAME-009]. First 80 chars of the string literal: "
                 f"`{preview}`")
            findings += 1
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-diagnostic-format.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_diagnostic_format(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
