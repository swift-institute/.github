#!/usr/bin/env python3
"""validate-file-naming.py — verify file naming conventions.

Wave 1 mechanization (2026-05-10) — companion to validate-file-naming.yml.
Wave 4 extension (2026-05-11) — [API-IMPL-007] extension-file basename check.

Rules checked:
  [API-IMPL-006] File names MUST match the type's full nested path with
                 dots — e.g., `Array.Dynamic.swift`, not `DynamicArray.swift`.
                 Mechanical narrow check: a `.swift` file in Sources/ whose
                 basename contains NO dots AND matches the compound-name
                 pattern (uppercase-first followed by an internal capital
                 boundary) is a likely violation.
  [API-IMPL-007] Extension files MUST use the `+` suffix pattern or the
                 where-clause shape. Mechanical narrow check: a `.swift`
                 file in Sources/ whose top-level declarations are ALL
                 `extension` blocks (no `struct` / `class` / `enum` /
                 `actor` / `protocol` / `typealias` declared at file scope)
                 MUST have `+` in its basename OR carry a ` where `
                 segment matching the where-clause shape. The "extension
                 only" file shape is the canonical extension-file signal.

Detection scope:
- `Sources/**/*.swift`. Test, Experiment, Example, and Benchmark trees are
  excluded by directory name (parallels `[API-IMPL-005]` SingleTypePerFile).
- Files whose basename is `Package`, `exports`, `Exports` are exempt
  (build-system / re-export files don't carry type declarations).
- Files whose basename is a `+`-suffixed extension form (`Foo+Sequence.swift`)
  per `[API-IMPL-007]` are exempt (the basename's `+` separator marks it as
  the conformance-extension shape, not the dotted-nested-type shape).
- Files whose basename is in the form `Foo where ...swift` per
  `[API-IMPL-007]`'s where-clause shape are exempt.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

# Detect compound name: starts uppercase, has at least one internal capital
# boundary (lowercase→uppercase OR uppercase→uppercase→lowercase).
COMPOUND_RE = re.compile(
    r"^[A-Z][a-z0-9]+[A-Z]"               # FooBar
    r"|^[A-Z]+[a-z]"                       # XYError (X→Y→E acronym→word)
)
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


def is_pure_extension_file(text: str) -> bool:
    """Return True iff the source has at least one top-level `extension`
    declaration AND no top-level type / func / var / let declarations.
    """
    if not TOP_LEVEL_EXTENSION_RE.search(text):
        return False
    if TOP_LEVEL_TYPE_RE.search(text):
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
        if is_compound_basename(basename):
            emit(repo, "API-IMPL-006",
                 f"file name `{f.relative_to(repo_root)}` is a compound name "
                 f"without dot separation — file names MUST match the type's "
                 f"full nested path with dots (e.g., `Array.Dynamic.swift` "
                 f"not `DynamicArray.swift`) per [API-IMPL-006]")
            findings += 1
        # [API-IMPL-007] — pure-extension files MUST have `+` or where-clause.
        if basename in EXEMPT_BASENAMES:
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if is_pure_extension_file(text):
            findings += validate_extension_file_basename(repo, f, repo_root)
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-file-naming.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_file_naming(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
