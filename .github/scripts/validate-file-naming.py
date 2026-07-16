#!/usr/bin/env python3
"""validate-file-naming.py — verify file naming conventions.

Wave 1 mechanization (2026-05-10) — companion to validate-file-naming.yml.
Wave 4 extension (2026-05-11) — [API-IMPL-007] extension-file basename check.
Pilot 9 extension (2026-05-14) — [TEST-009] test-file naming check folded in.

Rules checked:
  [API-IMPL-006] File names in Sources/ MUST match the type's full nested
                 path with dots — e.g., `Array.Dynamic.swift`, not
                 `DynamicArray.swift`. Mechanical narrow check: a `.swift`
                 file in Sources/ whose basename contains NO dots AND
                 matches the compound-name pattern (uppercase-first followed
                 by an internal capital boundary) is a candidate. It is a
                 violation only when no top-level declaration or extension
                 target exactly matches that basename.
  [API-IMPL-007] Extension files in Sources/ MUST use the `+` suffix pattern
                 or the where-clause shape. Mechanical narrow check: a
                 `.swift` file in Sources/ whose top-level declarations are
                 ALL `extension` blocks (no `struct` / `class` / `enum` /
                 `actor` / `protocol` / `typealias` declared at file scope)
                 MUST have `+` in its basename OR carry a ` where `
                 segment matching the where-clause shape.
  [TEST-009]     Test files MUST be named `{TypePath} Tests.swift`
                 (space before "Tests", mirroring the type hierarchy).
                 Mechanical check: in `Tests/{Target} Tests/` directories,
                 a `.swift` file whose basename ends with `Tests.swift`
                 but NOT with ` Tests.swift` (space before "Tests") is a
                 violation. Carve-outs match Sources/ patterns: skip
                 Tests/Support/, /Fixtures/, basenames with `+` or `where`,
                 build-system exemptions.

Detection scope:
- `Sources/**/*.swift` for [API-IMPL-006]/[API-IMPL-007]. Test, Experiment,
  Example, and Benchmark trees excluded by directory name.
- `Tests/**/*.swift` for [TEST-009]. Tests/Support/ and /Fixtures/ excluded.
- Files whose basename is `Package`, `exports`, `Exports` are exempt
  (build-system / re-export files don't carry type declarations).
- Files whose basename is a `+`-suffixed extension form (`Foo+Sequence.swift`)
  per `[API-IMPL-007]` are exempt.
- Files whose basename is in the form `Foo where ...swift` per
  `[API-IMPL-007]`'s where-clause shape are exempt.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

EXEMPT_BASENAMES = {"Package", "exports", "Exports"}


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def is_compound_basename(basename: str) -> bool:
    """Return True iff `basename` looks like a compound type name without
    dot separation. Compound = uppercase-first + internal capital boundary
    OR acronym→word (e.g., `IOError`).
    """
    if "." in basename:
        return False
    if basename in EXEMPT_BASENAMES:
        return False
    if "+" in basename:
        return False
    if "where " in basename or " where" in basename:
        return False
    if "_" in basename:
        # Spec-namespace forms (`RFC_4122`, `ISO_9945`) — exempt.
        return False
    if not basename or not basename[0].isupper():
        return False
    # Word-boundary count: ≥2 words ⇒ compound.
    words = 1
    chars = list(basename)
    i = 1
    while i < len(chars):
        prev = chars[i - 1]
        curr = chars[i]
        nxt = chars[i + 1] if i + 1 < len(chars) else None
        if curr.isupper():
            if prev.islower():
                words += 1
            elif prev.isupper() and nxt is not None and nxt.islower():
                words += 1
        if words >= 2:
            return True
        i += 1
    return False


# Match the top-level declarations and extension targets that can establish
# filename parity for [API-IMPL-006]. This deliberately mirrors the accepted
# release-wave adjudication implementation: a compound top-level declaration
# is not itself an API-IMPL-006 violation when its filename matches. Any
# separate type-naming concern belongs to its owning rule.
TYPE_DECL_RE = re.compile(
    r"(?m)^(?:[ \t]*)"
    r"(?:(?:public|internal|package|private|fileprivate|open|final|indirect|nonisolated|"
    r"@\w+(?:\([^\n]*\))?)\s+)*"
    r"(?P<kind>struct|class|enum|actor|protocol|typealias)\s+"
    r"(?P<name>`?[^\s:<>{=(]+`?)"
)
EXTENSION_DECL_RE = re.compile(
    r"(?m)^(?:[ \t]*)"
    r"(?:(?:public|internal|package|private|fileprivate|open|final|indirect|nonisolated|"
    r"@\w+(?:\([^\n]*\))?)\s+)*"
    r"extension\s+(?P<name>[^\s:{]+)"
)


def mask_non_code(text: str) -> str:
    """Mask comments and string literals while preserving offsets/newlines."""
    output = list(text)
    index = 0
    block_depth = 0
    string = False
    triple = False
    while index < len(text):
        if block_depth:
            if text.startswith("/*", index):
                output[index:index + 2] = "  "
                block_depth += 1
                index += 2
                continue
            if text.startswith("*/", index):
                output[index:index + 2] = "  "
                block_depth -= 1
                index += 2
                continue
            if text[index] != "\n":
                output[index] = " "
            index += 1
            continue
        if string:
            if triple and text.startswith('"""', index):
                output[index:index + 3] = "   "
                triple = False
                string = False
                index += 3
                continue
            if not triple and text[index] == '"' and (index == 0 or text[index - 1] != "\\"):
                output[index] = " "
                string = False
                index += 1
                continue
            if text[index] != "\n":
                output[index] = " "
            index += 1
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            output[index:end] = " " * (end - index)
            index = end
            continue
        if text.startswith("/*", index):
            output[index:index + 2] = "  "
            block_depth = 1
            index += 2
            continue
        if text.startswith('"""', index):
            output[index:index + 3] = "   "
            string = True
            triple = True
            index += 3
            continue
        if text[index] == '"':
            output[index] = " "
            string = True
        index += 1
    return "".join(output)


def brace_depths(text: str, positions: set[int]) -> dict[int, int]:
    """Return lexical brace depth at each requested source position."""
    depth = 0
    output: dict[int, int] = {}
    for index, character in enumerate(text):
        if index in positions:
            output[index] = depth
        if character == "{":
            depth += 1
        elif character == "}":
            depth = max(0, depth - 1)
    return output


def has_matching_top_level_declared_path(text: str, basename: str) -> bool:
    """Return True when a top-level declaration/extension target matches."""
    masked = mask_non_code(text)
    matches = (
        list(TYPE_DECL_RE.finditer(masked))
        + list(EXTENSION_DECL_RE.finditer(masked))
    )
    depths = brace_depths(masked, {match.start() for match in matches})
    for match in matches:
        name = match.group("name").strip("`").split("<", 1)[0]
        if name == basename and depths.get(match.start()) == 0:
            return True
    return False


# Detect top-level type declarations: any `struct|class|enum|actor|protocol|
# typealias|func|var|let` at the file's column-0 position (optionally
# preceded by access modifiers / attributes). The presence of any one of
# these marks the file as a "type" file rather than a pure-extension file.
TOP_LEVEL_TYPE_RE = re.compile(
    r"^(?:[a-zA-Z@_][\w@()]*[ \t]+)*"
    r"(?:struct|class|enum|actor|protocol|typealias|func|var|let)\s+",
    re.MULTILINE,
)
TOP_LEVEL_EXTENSION_RE = re.compile(
    r"^(?:[a-zA-Z@_][\w@()]*[ \t]+)*extension\s+",
    re.MULTILINE,
)

# Detect nested type declarations at non-zero indentation. The institute's
# canonical namespace-dispatch pattern declares nested types inside a
# parent-namespace extension:
#
#     extension Sequence {
#         public enum Drop { }
#     }
#
#     extension Sequence.Borrowing {
#         public protocol `Protocol`: ~Copyable, ~Escapable { ... }
#     }
#
# Such a file DECLARES the nested type even though all top-level constructs
# are extensions. It is NOT a pure-extension file per [API-IMPL-007] — the
# filename `Sequence.Drop.swift` mirrors the nested type path and satisfies
# [API-IMPL-006]. Only `struct|class|enum|actor|protocol|typealias` are
# included here (not `func|var|let`) because the latter are normal
# extension content (stored properties, methods) that do not promote the
# file to a type-declaring file.
NESTED_TYPE_RE = re.compile(
    r"^\s+(?:[a-zA-Z@_][\w@()]*[ \t]+)*"
    r"(?:struct|class|enum|actor|protocol|typealias)\s+",
    re.MULTILINE,
)


def is_pure_extension_file(text: str) -> bool:
    """Return True iff the source has at least one top-level `extension`
    declaration AND no type declarations anywhere — top-level OR nested
    inside an extension or other top-level construct.

    The nested-type check handles the institute namespace-dispatch pattern
    per [MOD-031] where types are declared inside a parent-namespace
    extension. Those files DECLARE types and must not be classified as
    pure-extension per [API-IMPL-007].
    """
    if not TOP_LEVEL_EXTENSION_RE.search(text):
        return False
    if TOP_LEVEL_TYPE_RE.search(text):
        return False
    if NESTED_TYPE_RE.search(text):
        return False
    return True


def validate_extension_file_basename(repo: str, file: Path, repo_root: Path) -> int:
    """For a pure-extension file, verify its basename carries either a
    `+` segment or a ` where ` segment per [API-IMPL-007]. Return finding
    count (0 or 1).
    """
    basename = file.stem
    if "+" in basename:
        return 0
    if " where " in basename:
        return 0
    emit(repo, "API-IMPL-007",
         f"file name `{file.relative_to(repo_root)}` contains only extension "
         f"declarations but its basename lacks a `+` conformance segment "
         f"(`Foo+Sequence.swift`) or a ` where ` clause "
         f"(`Carrier where Underlying == Self.swift`) — extension files "
         f"MUST carry one of those discriminators per [API-IMPL-007]")
    return 1


def validate_file_naming(repo: str, repo_root: Path) -> int:
    findings = 0
    sources = repo_root / "Sources"
    if not sources.is_dir():
        return 0
    swift_files: list[Path] = []
    for p in sources.rglob("*.swift"):
        relative = p.relative_to(repo_root)
        if any(seg.startswith(".") for seg in relative.parts):
            continue
        # Skip test / experiment / example trees that may live nested in Sources.
        if any(seg in {"Tests", "Experiments", "Examples", "Benchmarks"}
               for seg in relative.parts):
            continue
        swift_files.append(p)
    for f in swift_files:
        basename = f.stem  # `<name>` from `<name>.swift`
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if (is_compound_basename(basename)
                and not has_matching_top_level_declared_path(text, basename)):
            emit(repo, "API-IMPL-006",
                 f"file name `{f.relative_to(repo_root)}` has a compound "
                 f"basename that matches no top-level declaration or extension "
                 f"target — file names MUST match the declared full type path "
                 f"with dots per [API-IMPL-006]")
            findings += 1
        # [API-IMPL-007] — pure-extension files MUST have `+` or where-clause.
        if basename in EXEMPT_BASENAMES:
            continue
        if is_pure_extension_file(text):
            findings += validate_extension_file_basename(repo, f, repo_root)
    return findings


def validate_test_file_naming(repo: str, repo_root: Path) -> int:
    """[TEST-009] — test files in `Tests/{Target} Tests/` directories MUST
    end with ` Tests.swift` (space before "Tests"). Files ending with
    `Tests.swift` WITHOUT the space are compound-name violations.
    Other carve-outs match the Sources/-side patterns above.
    """
    findings = 0
    tests = repo_root / "Tests"
    if not tests.is_dir():
        return 0
    for p in tests.rglob("*.swift"):
        relative = p.relative_to(repo_root)
        parts = relative.parts
        if any(seg.startswith(".") for seg in parts):
            continue
        # Support / Fixtures directories carry the Test Support module's
        # own files and fixture types — different naming convention.
        if "Support" in parts or "Fixtures" in parts:
            continue
        basename = p.stem  # `<name>` from `<name>.swift`
        if basename in EXEMPT_BASENAMES:
            continue
        if "+" in basename:
            continue  # [API-IMPL-007] extension form
        if " where " in basename or basename.endswith(" where"):
            continue  # [API-IMPL-007] where-clause shape
        # Only flag files whose basename ends with "Tests" (i.e., this is
        # a test file by naming convention). Fixture types and helper
        # files in test directories don't end with "Tests" — they're out
        # of scope (their naming is governed by [API-IMPL-006] style).
        if not basename.endswith("Tests"):
            continue
        # Conforming form: `<TypePath> Tests` (literal space before "Tests").
        # Non-conforming: `<Compound>Tests` (no space), `<X>.Tests` (dot
        # instead of space), etc.
        if basename.endswith(" Tests"):
            continue
        emit(repo, "TEST-009",
             f"file name `{p.relative_to(repo_root)}` does not match the "
             f"`{{TypePath}} Tests.swift` shape (space before \"Tests\") — "
             f"per [TEST-009] test filenames MUST mirror the type "
             f"hierarchy with a space-separated `Tests` suffix")
        findings += 1
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-file-naming.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_file_naming(repo, repo_root)
    findings += validate_test_file_naming(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
