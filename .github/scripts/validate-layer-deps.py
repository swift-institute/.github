#!/usr/bin/env python3
"""validate-layer-deps.py — verify platform-stack layer & dependency invariants.

Wave 2 mechanization (2026-05-11) — companion to validate-layer-deps.yml.

Rules checked (v1):
  [PLAT-ARCH-008]  Non-platform-stack packages MUST NOT import platform-
                   specific L2-spec or L3-policy modules — consumers
                   `import Kernel`, not `import Darwin_Kernel_Standard` /
                   `import Linux_Kernel_Standard` / `import POSIX_Kernel`
                   etc. The platform stack itself (L1 platform-aware
                   primitives, L2 spec, L3-policy, L3-unifier, L3-domain
                   `swift-file-system`) is exempt — those packages live
                   precisely so the rest of the ecosystem doesn't need to.
  [PLAT-ARCH-008h] Within-L3 sub-tiering composition matrix:
                   * L3-policy packages (swift-posix, swift-darwin,
                     swift-linux, swift-windows) MUST NOT depend on any
                     L3-unifier or L3-domain package (upward composition
                     forbidden).
                   * L3-domain packages (swift-file-system) MUST NOT depend
                     on L3-policy packages directly — they MUST go through
                     an L3-unifier per the matrix.

Rules listed in the Wave 2 handoff that are NOT mechanized in this script
(documented for traceability — semantic checks beyond scope of pure file/
import inspection):
  [PLAT-ARCH-008a] Domain Authority Exception — provisional, requires user
                   confirmation of the four criteria; the hard line (raw
                   Darwin/Glibc/Musl/WinSDK imports outside L2 spec) is
                   already mechanized by [PLAT-ARCH-008j] in
                   validate-platform-architecture.py.
  [PLAT-ARCH-008b] Conditional public API surface — distinguishing public
                   enum-case `#if` blocks from internal-only `#if` blocks
                   without parsing Swift is unreliable; the L1 sub-case
                   ("no `#if os` in L1") is fully mechanized at
                   [PLAT-ARCH-008c].
  [PLAT-ARCH-008d] Syscall-vs-policy test — semantic distinction between
                   "syscall dispatch" and "domain policy" cannot be derived
                   from file content; ecosystem audits cover this rule.
  [PLAT-ARCH-008e] L3-unifier composition discipline — verifying that the
                   unifier composes the L3-policy tier (not L2 raw) when an
                   L3-policy wrapper exists requires a workspace-wide symbol
                   registry; surface this gap to the principal if/when the
                   registry is built.
  [PLAT-ARCH-008i] L3-policy peer composition (swift-windows MUST NOT
                   import POSIX_*) is already mechanized at
                   validate-platform-architecture.py.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

from validate_lib import emit

# ---- Platform-stack registry --------------------------------------------
#
# L1 platform-aware primitives: live with the rest of swift-primitives, but
# are exempt from the [PLAT-ARCH-008] consumer-import rule because they are
# the foundation the rest of the stack composes on.
L1_PLATFORM_PRIMITIVES = frozenset({
    "swift-kernel-primitives",
    "swift-cpu-primitives",
    "swift-darwin-primitives",
    "swift-linux-primitives",
    "swift-windows-primitives",
})

# L2 spec packages.
L2_SPEC = frozenset({
    "swift-iso-9945",
    "swift-darwin-standard",
    "swift-linux-standard",
    "swift-windows-32",
    "swift-windows-standard",  # historical name; renamed to swift-windows-32 2026-04-30
})

# L3-policy packages — per-spec policy wrappers.
L3_POLICY = frozenset({
    "swift-posix",
    "swift-darwin",
    "swift-linux",
    "swift-windows",
})

# L3-unifier packages — cross-platform unification surface.
L3_UNIFIER = frozenset({
    "swift-kernel",
    "swift-strings",
    "swift-paths",
    "swift-ascii",
    "swift-systems",
    "swift-io",
    "swift-threads",
    "swift-environment",
})

# L3-domain packages — domain-specific composition over L3-unifier.
L3_DOMAIN = frozenset({
    "swift-file-system",
})

PLATFORM_STACK = (
    L1_PLATFORM_PRIMITIVES
    | L2_SPEC
    | L3_POLICY
    | L3_UNIFIER
    | L3_DOMAIN
)

# ---- Module-name → package mapping for import-time detection -------------
#
# The platform-specific module names that consumers MUST NOT directly import
# per [PLAT-ARCH-008]. The reverse mapping module → package name lets us
# point the diagnostic at the canonical package.
PLATFORM_IMPORT_FORBIDDEN: dict[str, str] = {
    # L2 platform-spec modules
    "Darwin_Kernel_Standard": "swift-darwin-standard",
    "Linux_Kernel_Standard": "swift-linux-standard",
    "Windows_32_Core": "swift-windows-32",
    "ISO_9945_Core": "swift-iso-9945",
    # L3-policy modules
    "Darwin_Kernel": "swift-darwin",
    "Linux_Kernel": "swift-linux",
    "Windows_Kernel": "swift-windows",
    "POSIX_Kernel": "swift-posix",
}

# ---- Package.swift dependency parsing ------------------------------------
#
# Sufficient regex to extract package names appearing on the right-hand side
# of `.product(... package: "<name>" ...)` declarations.
PRODUCT_DEP = re.compile(r'\.product\([^)]*package:\s*"([^"]+)"', re.DOTALL)

# ---- Source import parsing -----------------------------------------------
#
# Match `import X`, `@_exported public import X`, `public import X`, etc.
# Capture group 1 is the module name. Restricted to top-level import
# statements (not lexically inside #if blocks beyond grep granularity).
IMPORT_RE = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
    r"(?:public[ \t]+|package[ \t]+|internal[ \t]+|private[ \t]+|fileprivate[ \t]+)?"
    r"import[ \t]+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def is_in_platform_stack(repo_name: str, deps: list[str]) -> bool:
    """A package is part of the platform stack if it is in the explicit
    registry OR declares Package.swift dependencies on any platform
    package (L2 spec or L3-policy). The latter rule lets the validator
    classify domain-specific L3-unifiers (`swift-random`, `swift-process`,
    `swift-clocks`, etc.) per [PLAT-ARCH-021] without enumerating the
    full ecosystem in the registry.

    A package outside this set is a consumer in the [PLAT-ARCH-008] sense
    and MUST import `Kernel` (or other L3-unifier surface) only.
    """
    if repo_name in PLATFORM_STACK:
        return True
    stack_dep_signals = L2_SPEC | L3_POLICY
    return any(dep in stack_dep_signals for dep in deps)


def parse_package_deps(package_swift: Path) -> list[str]:
    """Return the list of package names referenced in `.product(package:`
    declarations in `Package.swift`. Sorted, deduplicated.
    """
    if not package_swift.is_file():
        return []
    body = package_swift.read_text()
    deps: set[str] = set()
    for m in PRODUCT_DEP.finditer(body):
        deps.add(m.group(1))
    return sorted(deps)


def iter_swift_files(sources: Path, repo_root: Path):
    if not sources.is_dir():
        return
    paths: list[Path] = []
    for p in sources.rglob("*.swift"):
        relative = p.relative_to(repo_root)
        if any(seg.startswith(".") for seg in relative.parts):
            continue
        paths.append(p)
    paths.sort()
    yield from paths


def check_plat_arch_008(repo: str, repo_root: Path) -> int:
    """[PLAT-ARCH-008]: non-platform-stack packages MUST NOT import
    platform-specific L2/L3 modules directly.
    """
    repo_name = repo.split("/")[-1]
    deps = parse_package_deps(repo_root / "Package.swift")
    if is_in_platform_stack(repo_name, deps):
        return 0
    sources = repo_root / "Sources"
    findings = 0
    seen: set[tuple[str, str]] = set()  # (module, file) — one finding per pair
    for f in iter_swift_files(sources, repo_root):
        try:
            content = f.read_text()
        except Exception:
            continue
        for m in IMPORT_RE.finditer(content):
            module = m.group(1)
            if module in PLATFORM_IMPORT_FORBIDDEN:
                key = (module, str(f.relative_to(repo_root)))
                if key in seen:
                    continue
                seen.add(key)
                source_pkg = PLATFORM_IMPORT_FORBIDDEN[module]
                emit(repo, "PLAT-ARCH-008",
                     f"{f.relative_to(repo_root)}: non-platform-stack package "
                     f"imports `{module}` (from {source_pkg!r}); per "
                     f"[PLAT-ARCH-008] consumers MUST import the L3-unifier "
                     f"surface (`import Kernel`, etc.), not platform-specific "
                     f"L2-spec or L3-policy modules directly")
                findings += 1
    return findings


def check_plat_arch_008h(repo: str, repo_root: Path) -> int:
    """[PLAT-ARCH-008h]: L3-policy MUST NOT depend on L3-unifier/L3-domain;
    L3-domain MUST NOT depend on L3-policy directly (must go through
    L3-unifier).
    """
    repo_name = repo.split("/")[-1]
    package_swift = repo_root / "Package.swift"
    deps = parse_package_deps(package_swift)
    findings = 0
    if repo_name in L3_POLICY:
        for dep in deps:
            if dep in L3_UNIFIER:
                emit(repo, "PLAT-ARCH-008h",
                     f"Package.swift declares dep on `{dep}` (L3-unifier); "
                     f"L3-policy ({repo_name}) MUST NOT depend on L3-unifier "
                     f"(upward composition forbidden per [PLAT-ARCH-008h])")
                findings += 1
            elif dep in L3_DOMAIN:
                emit(repo, "PLAT-ARCH-008h",
                     f"Package.swift declares dep on `{dep}` (L3-domain); "
                     f"L3-policy ({repo_name}) MUST NOT depend on L3-domain "
                     f"(upward composition forbidden per [PLAT-ARCH-008h])")
                findings += 1
    if repo_name in L3_DOMAIN:
        for dep in deps:
            if dep in L3_POLICY:
                emit(repo, "PLAT-ARCH-008h",
                     f"Package.swift declares dep on `{dep}` (L3-policy); "
                     f"L3-domain ({repo_name}) MUST go through L3-unifier per "
                     f"[PLAT-ARCH-008h], not depend on L3-policy directly")
                findings += 1
    return findings


def validate_layer_deps(repo: str, repo_root: Path) -> int:
    findings = 0
    findings += check_plat_arch_008(repo, repo_root)
    findings += check_plat_arch_008h(repo, repo_root)
    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-layer-deps.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_layer_deps(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
