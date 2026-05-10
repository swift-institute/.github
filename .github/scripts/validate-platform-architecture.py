#!/usr/bin/env python3
"""validate-platform-architecture.py — verify platform-stack invariants.

Wave 2b finalization (2026-05-10) — companion to validate-platform-architecture.yml.

Rules checked (v1):
  [PLAT-ARCH-008c] L1 Primitives packages MUST NOT contain `#if os(...)` /
                   `#if canImport(...)` conditionals in any source file.
  [PLAT-ARCH-008i] swift-windows packages MUST NOT `import POSIX_*` modules.
  [PLAT-ARCH-008j] `import Darwin/Glibc/Musl/WinSDK` is restricted to L2 spec
                   packages (swift-iso-9945, swift-linux-standard,
                   swift-darwin-standard, swift-windows-32). All other packages
                   that grep matches are violations.
  [PLAT-ARCH-023]  swift-iso-9945 MUST NOT take a package or target dependency
                   on swift-linux-standard or swift-darwin-standard.
  [PATTERN-005]    All packages MUST require Swift 6.3+ and use Swift 6 lang mode.
  [PATTERN-006]    Packages SHOULD enable upcoming features (ExistentialAny,
                   InternalImportsByDefault, MemberImportVisibility).
"""
from __future__ import annotations
import re
import subprocess
import sys
from pathlib import Path

L2_PLATFORM_ALLOWLIST = {
    "swift-iso-9945",
    "swift-linux-standard",
    "swift-darwin-standard",
    "swift-windows-32",
}

REQUIRED_TOOLS_VERSION = re.compile(r"^// swift-tools-version:\s*([0-9.]+)")
LANG_MODE_V6 = re.compile(r"swiftLanguageModes:\s*\[\s*\.v6\s*\]")
PLATFORM_IMPORT = re.compile(r"^[ \t]*import[ \t]+(Darwin|Glibc|Musl|WinSDK)\b", re.MULTILINE)
POSIX_IMPORT = re.compile(r"^[ \t]*(?:@[^\s]+\s+)*(?:public[ \t]+|package[ \t]+|internal[ \t]+)?import[ \t]+POSIX_\w+", re.MULTILINE)
PLATFORM_CONDITIONAL = re.compile(r"^\s*#if\s+(os|canImport)\b", re.MULTILINE)
UPCOMING_FEATURES = ("ExistentialAny", "InternalImportsByDefault", "MemberImportVisibility")


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def is_l1_primitives(repo_name: str) -> bool:
    """Match swift-*-primitives packages (excluding L1 platform packages on the allowlist)."""
    if not repo_name.endswith("-primitives"):
        return False
    # L1 platform packages are exempt (kernel-primitives, cpu-primitives are at L1
    # but allowed platform-conditional code per [MOD-EXCEPT-001]).
    return repo_name not in {"swift-kernel-primitives", "swift-cpu-primitives"}


def validate_platform_architecture(repo: str, repo_root: Path) -> int:
    findings = 0
    repo_name = repo.split("/")[-1]
    package_swift = repo_root / "Package.swift"
    sources = repo_root / "Sources"

    # [PATTERN-005] swift-tools-version
    if package_swift.is_file():
        first_line = package_swift.read_text().splitlines()[:1]
        if first_line:
            m = REQUIRED_TOOLS_VERSION.match(first_line[0])
            if not m:
                emit(repo, "PATTERN-005",
                     f"Package.swift first line not `// swift-tools-version: X.Y[.Z]`")
                findings += 1
            else:
                version = m.group(1)
                parts = [int(x) for x in version.split(".")]
                if parts < [6, 3]:
                    emit(repo, "PATTERN-005",
                         f"Package.swift swift-tools-version is {version}; required ≥ 6.3")
                    findings += 1
        body = package_swift.read_text()
        if not LANG_MODE_V6.search(body):
            emit(repo, "PATTERN-005",
                 "Package.swift missing `swiftLanguageModes: [.v6]` declaration")
            findings += 1
        # [PATTERN-006] upcoming features
        for feat in UPCOMING_FEATURES:
            if f'enableUpcomingFeature("{feat}")' not in body:
                emit(repo, "PATTERN-006",
                     f"Package.swift does not enableUpcomingFeature({feat!r}) "
                     f"(SHOULD per [PATTERN-006])")
                findings += 1
        # [PLAT-ARCH-023] iso-9945 dep direction
        if repo_name == "swift-iso-9945":
            if 'package: "swift-linux-standard"' in body or 'package: "swift-darwin-standard"' in body:
                emit(repo, "PLAT-ARCH-023",
                     "swift-iso-9945 declares dependency on swift-linux-standard or "
                     "swift-darwin-standard (forbidden — iso-9945 is the POSIX-shared base)")
                findings += 1

    # Sources scans
    if sources.is_dir():
        # Build file list
        swift_files: list[Path] = []
        for p in sources.rglob("*.swift"):
            if any(seg.startswith(".") for seg in p.parts):
                continue
            swift_files.append(p)

        # [PLAT-ARCH-008c] L1 primitives platform-conditional ban
        if is_l1_primitives(repo_name):
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                m = PLATFORM_CONDITIONAL.search(content)
                if m:
                    emit(repo, "PLAT-ARCH-008c",
                         f"L1 primitives package contains platform-conditional code at "
                         f"{f.relative_to(repo_root)} (forbidden per [PLAT-ARCH-008c])")
                    findings += 1
                    break  # one finding per file is enough

        # [PLAT-ARCH-008i] swift-windows must not import POSIX_*
        if repo_name.startswith("swift-windows"):
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                if POSIX_IMPORT.search(content):
                    emit(repo, "PLAT-ARCH-008i",
                         f"{f.relative_to(repo_root)}: swift-windows-* MUST NOT import POSIX_* "
                         "(forbidden per [PLAT-ARCH-008i])")
                    findings += 1
                    break

        # [PLAT-ARCH-008j] platform stdlib import restricted to L2 allowlist
        if repo_name not in L2_PLATFORM_ALLOWLIST:
            offenders: list[Path] = []
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                if PLATFORM_IMPORT.search(content):
                    offenders.append(f.relative_to(repo_root))
            if offenders:
                emit(repo, "PLAT-ARCH-008j",
                     f"non-L2 package imports Darwin/Glibc/Musl/WinSDK in "
                     f"{len(offenders)} file(s); first offender = {offenders[0]} "
                     "(forbidden per [PLAT-ARCH-008j] — restricted to swift-iso-9945, "
                     "swift-linux-standard, swift-darwin-standard, swift-windows-32)")
                findings += 1

    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-platform-architecture.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_platform_architecture(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
