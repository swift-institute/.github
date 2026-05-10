#!/usr/bin/env python3
"""validate-file-naming.py — verify file naming conventions.

Wave 1 mechanization (2026-05-10) — companion to validate-file-naming.yml.

Rules checked:
  [API-IMPL-006] File names MUST match the type's full nested path with
                 dots — e.g., `Array.Dynamic.swift`, not `DynamicArray.swift`.
                 Mechanical narrow check: a `.swift` file in Sources/ whose
                 basename contains NO dots AND matches the compound-name
                 pattern (uppercase-first followed by an internal capital
                 boundary) is a likely violation.

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
