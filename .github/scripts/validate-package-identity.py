#!/usr/bin/env python3
"""validate-package-identity.py — [PKG-DEP-008] mirror-only `.product(package:)` aliases.

Manifest-only lint (parse Package.swift, no build; sub-second, no resolve).

Rule checked: [PKG-DEP-008] — every consumer `.product(name:, package: X)`
MUST spell the dependency's canonical off-machine identity: the
`.package(url:)` URL's last path component minus `.git` (for
`.package(path:)` deps, the dep's git repo name — read from its
`.git/config` remote origin — NOT the on-disk dir basename when they
differ). SwiftPM identity is mirror-dependent: WITH the global mirror both
the local-dir basename and the URL repo-name resolve; WITHOUT it (clean
room / fresh clone) only the URL repo-name does — the basename fails with
`unknown package '<basename>'`. A mirror-backed `swift package resolve`
does NOT validate this; only a clean-room resolve ([CI-112]) does — this
lint is the fast local complement.

Detection:
  1. Parse each Package.swift under <repo-root> (skipping .build/, .git/,
     node_modules/) for `.package(url:)` / `.package(path:)` declarations.
  2. Compute each dep's canonical identity (URL last component minus .git;
     path deps via .git/config origin, falling back to the dir basename).
     A legacy `.package(name: "N", url:)` declared name is also accepted —
     pre-5.6 manifests bind identity to it on every machine.
  3. For every target `.product(name:, package: X)`: flag X when it is not
     a canonical identity (case-insensitive per SwiftPM PackageIdentity).
     When the machine-local SwiftPM mirrors.json (or a path-dep basename)
     identifies X as a mirror-only alias of a declared dep, the finding
     names the canonical identity to rewrite to.

Output: TSV findings `repo<TAB>PKG-DEP-008<TAB>message` (validate_lib.emit).
Exit 0 always (findings are counted by the harness / aggregation layer).

Usage:
  validate-package-identity.py <repo-name> <repo-root>

Provenance: HANDOFF-meta-ecosystem-followups §1(a) staged spec
(seat-approved 2026-07-05, verbatim); promoted via /promote-rule per
HANDOFF-mechanization-arc W1. Outcome record:
swift-institute/Audits/PROMOTE-PKG-DEP-008-2026-07-06.md.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

from validate_lib import emit

RULE = "PKG-DEP-008"

# .claude covers harness-internal scratch worktrees (.claude/worktrees/…).
SKIP_DIRS = {".build", ".git", ".swiftpm", ".claude", "node_modules", "checkouts"}

RE_URL_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"(?P<name>[^"]+)"\s*,\s*)?url:\s*"(?P<url>[^"]+)"'
)
RE_PATH_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"(?P<name>[^"]+)"\s*,\s*)?path:\s*"(?P<path>[^"]+)"'
)
# `.product(...)` argument windows never nest parens in practice; the [^)]*
# window tolerates moduleAliases:/condition: between name: and package:.
RE_PRODUCT = re.compile(
    r'\.product\s*\(\s*name:\s*"(?P<prod>[^"]+)"[^)]*?package:\s*"(?P<pkg>[^"]+)"'
)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    # Line comments; `(?<!:)` keeps `https://…` URLs intact.
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def url_repo_name(url: str) -> str:
    last = url.rstrip("/").rsplit("/", 1)[-1]
    return last[:-4] if last.endswith(".git") else last


def git_origin_repo_name(pkg_dir: Path) -> str | None:
    """Best-effort read of <pkg_dir>/.git/config remote-origin repo name.
    Handles .git-as-file (worktree/submodule gitdir pointer). Returns None
    when no origin is derivable — callers fall back to the dir basename
    (matching the mirrors.json synthesis convention for origin-less clones).
    """
    git = pkg_dir / ".git"
    try:
        if git.is_file():
            m = re.match(r"gitdir:\s*(.+)", git.read_text(encoding="utf-8").strip())
            if not m:
                return None
            git = (pkg_dir / m.group(1)).resolve()
        config = git / "config"
        if not config.is_file():
            return None
        section = None
        for line in config.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line.startswith("["):
                section = line
            elif section == '[remote "origin"]' and line.startswith("url"):
                url = line.split("=", 1)[1].strip()
                return url_repo_name(url)
    except OSError:
        return None
    return None


def load_mirror_basenames() -> dict[str, str]:
    """{mirror-dir-basename (lower) → original-url repo name} from the
    machine-local SwiftPM mirrors.json, when present (dev machines only)."""
    path = Path.home() / "Library/org.swift.swiftpm/configuration/mirrors.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    out = {}
    for entry in data.get("object", []):
        original, mirror = entry.get("original", ""), entry.get("mirror", "")
        if original and mirror and "://" not in mirror:
            out[Path(mirror).name.lower()] = url_repo_name(original)
    return out


def manifests(root: Path):
    # os.walk with in-place pruning — rglob would walk .build/checkouts
    # trees (thousands of dirs) before the filter could reject them.
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "Package.swift" in filenames:
            found.append(Path(dirpath) / "Package.swift")
    return sorted(found)


def check_manifest(repo: str, root: Path, manifest: Path, mirror_basenames: dict[str, str]) -> None:
    text = strip_comments(manifest.read_text(encoding="utf-8", errors="replace"))
    rel = manifest.relative_to(root)

    identities: dict[str, str] = {}   # lower-cased identity → display form
    aliases: dict[str, str] = {}      # lower-cased mirror-only alias → canonical

    for m in RE_URL_DEP.finditer(text):
        canonical = url_repo_name(m.group("url"))
        identities[canonical.lower()] = canonical
        if m.group("name"):  # legacy name: parameter binds identity everywhere
            identities[m.group("name").lower()] = m.group("name")

    for m in RE_PATH_DEP.finditer(text):
        dep_dir = (manifest.parent / m.group("path")).resolve()
        basename = dep_dir.name
        canonical = git_origin_repo_name(dep_dir) or basename
        identities[canonical.lower()] = canonical
        if m.group("name"):
            identities[m.group("name").lower()] = m.group("name")
        if basename.lower() != canonical.lower():
            aliases[basename.lower()] = canonical

    if not identities:
        return

    for m in RE_PRODUCT.finditer(text):
        ref = m.group("pkg")
        key = ref.lower()
        if key in identities:
            continue
        if key in aliases:
            emit(repo, RULE, f"{rel}: .product(name: \"{m.group('prod')}\", package: \"{ref}\") "
                             f"uses the local-dir basename; canonical off-machine identity is "
                             f"\"{aliases[key]}\" (mirror-only alias, fails off-machine)")
        elif key in mirror_basenames and mirror_basenames[key].lower() in identities:
            emit(repo, RULE, f"{rel}: .product(name: \"{m.group('prod')}\", package: \"{ref}\") "
                             f"is a mirror-only alias; canonical off-machine identity is "
                             f"\"{mirror_basenames[key]}\"")
        else:
            emit(repo, RULE, f"{rel}: .product(name: \"{m.group('prod')}\", package: \"{ref}\") "
                             f"matches no declared dependency identity — off-machine this fails "
                             f"with: unknown package '{ref}'")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])
    if not root.is_dir():
        print(f"# error: repo root not found: {root}", file=sys.stderr)
        return 2
    mirror_basenames = load_mirror_basenames()
    for manifest in manifests(root):
        check_manifest(repo, root, manifest, mirror_basenames)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
