#!/usr/bin/env python3
"""validate-dependency-hygiene.py — enforce [PKG-DEP-007] declared-dependency hygiene.

Check (v1, 2026-07-01):
  [PKG-DEP-007] Unused dependency — a top-level `.package(url:/path:)` whose
    identity is referenced by NO `.product(name:, package: "<id>")` anywhere in
    the manifest (targets OR dependency-helper extensions) is dead weight: with
    zero product references, none of the package's modules are importable under
    MemberImportVisibility, so the dependency is unused. Remove it — or, if a
    source imports one of its modules, ADD the missing `.product` to the
    importing target (the under-declared case).

    Suppress a deliberate transitive-collision override (a `.package` declared
    only to pin/redirect a transitive identity, referenced by no product) with a
    trailing `// lint:allow(unused-dependency)` on the declaration line.

Deferred sibling checks (see swift-institute/Audits/PROMOTE-PKG-DEP-007-2026-07-01.md):
  - Under-declared dependency (source imports a module whose product isn't
    declared on the importing target) — needs per-target source-import + module
    resolution a single-repo validator can't do without false positives.
  - Unused manifest helper (a manifest-local `static` helper referenced nowhere)
    — false-positive-prone on short helper names (`tests`, `standards`) that
    collide with product/string tokens; needs tighter discrimination.

Detection is comment-masked (commented-out `.package`/`.product` do not count)
and string-literal-aware (a `https://` inside a URL string is preserved).

Invocation: validate-dependency-hygiene.py <repo-name> <repo-root>
Output: TSV findings via validate_lib.emit; exit 0 (clean) / 1 (findings) / 2 (usage).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit

DECLARED_PKG = re.compile(r'\.package\(\s*(?:url|path):\s*"([^"]+)"', re.DOTALL)
PRODUCT_DEP = re.compile(
    r'\.product\(\s*name:\s*"[^"]+"\s*,\s*package:\s*"([^"]+)"',
    re.DOTALL,
)
OPT_OUT = "lint:allow(unused-dependency)"


def mask_comments(text: str) -> str:
    """Blank `//` and `/* */` comment CHARACTERS to spaces, preserving byte
    offsets and respecting string literals (so `https://` inside a `"..."` URL
    is not treated as a line comment).
    """
    out = list(text)
    i, n = 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
            if i + 1 < n:
                out[i + 1] = " "
            i += 2
            continue
        i += 1
    return "".join(out)


def _identity(url_or_path: str) -> str:
    """SwiftPM package identity = basename of the url/path, minus a `.git` suffix."""
    base = url_or_path.rstrip("/").split("/")[-1]
    if base.endswith(".git"):
        base = base[:-4]
    return base


def check_unused_dependency(repo: str, package_swift: Path) -> int:
    if not package_swift.is_file():
        return 0
    raw = package_swift.read_text(encoding="utf-8")
    masked = mask_comments(raw)  # commented-out .package/.product must not count
    used = {m.group(1) for m in PRODUCT_DEP.finditer(masked)}
    findings = 0
    seen: set[str] = set()
    for m in DECLARED_PKG.finditer(masked):
        identity = _identity(m.group(1))
        if identity in used or identity in seen:
            continue
        # The opt-out marker lives in a trailing comment (blanked in `masked`),
        # so read the marker off the RAW declaration line.
        ls = raw.rfind("\n", 0, m.start()) + 1
        le = raw.find("\n", m.start())
        line = raw[ls: le if le != -1 else len(raw)]
        if OPT_OUT in line:
            continue
        seen.add(identity)
        emit(
            repo,
            "PKG-DEP-007",
            f"Package.swift declares dependency '{identity}' but no target "
            f'references it via .product(package: "{identity}"); remove the '
            f"declaration — or if a source imports one of its modules, add the "
            f"missing .product to the importing target — per [PKG-DEP-007]. "
            f"Suppress a deliberate transitive-collision override with a "
            f"trailing `// lint:allow(unused-dependency)`.",
        )
        findings += 1
    return findings


def validate_dependency_hygiene(repo: str, repo_root: Path) -> int:
    return check_unused_dependency(repo, repo_root / "Package.swift")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-dependency-hygiene.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_dependency_hygiene(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
