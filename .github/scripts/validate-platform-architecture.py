#!/usr/bin/env python3
"""validate-platform-architecture.py — verify platform-stack invariants.

Wave 2b finalization (2026-05-10); Wave 2 consolidation (2026-05-11) moved
PATTERN-005 / PATTERN-006 to validate-package-shape.py to keep platform-stack
invariants and Swift-package shape conventions on separate validators; Wave 2
extension (2026-05-11) added [PLAT-ARCH-004], [PLAT-ARCH-005], [PLAT-ARCH-006],
[PLAT-ARCH-027] from the platform-skill mechanization list.

Rules checked (v2):
  [PLAT-ARCH-004]  Each platform L2 spec package MUST declare its platform
                   root namespace (`public enum Darwin` in swift-darwin-
                   standard, `Linux` in swift-linux-standard, `Windows` in
                   swift-windows-32, `ISO_9945` in swift-iso-9945).
  [PLAT-ARCH-005]  swift-kernel-primitives MUST NOT define `Kernel.Descriptor`
                   as a concrete type (struct/class/enum). The L2-canonical
                   Descriptor lives at the spec layer with an L3-policy
                   typealias and an L3-unifier typealias per the three-tier
                   chain. L1 hosts no Descriptor type.
  [PLAT-ARCH-006]  Each L3 platform foundation package (swift-darwin,
                   swift-linux, swift-windows, swift-posix) MUST re-export
                   its L2 spec layer via `@_exported public import` in at
                   least one source file. Detection looks for the L2
                   module-name prefix (Darwin_*, Linux_*, Windows_32_*,
                   ISO_9945_*) appearing in a `@_exported public import`
                   declaration.
  [PLAT-ARCH-007]  POSIX syscall wrappers (shared between Darwin and Linux)
                   MUST live in swift-iso-9945 (L2 POSIX spec). Curated POSIX-
                   function-call presence in swift-darwin-standard or
                   swift-linux-standard sources is a likely violation.
                   Wave 1 mechanization (2026-05-10).
  [PLAT-ARCH-008c] L1 Primitives packages MUST NOT contain `#if os(...)` /
                   `#if canImport(...)` conditionals in any source file.
  [PLAT-ARCH-008i] swift-windows packages MUST NOT `import POSIX_*` modules.
  [PLAT-ARCH-008j] `import Darwin/Glibc/Musl/WinSDK` is restricted to L2 spec
                   packages (swift-iso-9945, swift-linux-standard,
                   swift-darwin-standard, swift-windows-32). All other packages
                   that grep matches are violations.
  [PLAT-ARCH-023]  swift-iso-9945 MUST NOT take a package or target dependency
                   on swift-linux-standard or swift-darwin-standard.
  [PLAT-ARCH-027]  In platform-primitives packages (swift-darwin-primitives,
                   swift-linux-primitives, swift-windows-primitives), every
                   variant target's exports/Exports.swift MUST contain
                   `@_exported public import {Platform}_Primitives_Core` so
                   the platform root namespace flows without publishing the
                   Core target itself. Currently no such packages exist on
                   disk, so the check is defensive (it fires when they appear).

Rules listed in the Wave 2 handoff that are NOT mechanized here (documented
for traceability — semantic / pre-flight / ecosystem-wide checks beyond
single-package validation):
  [PLAT-ARCH-001]  Four-Level Platform Stack — architectural framing rule;
                   layer assignments are verifiable but require a workspace
                   registry rather than per-package state.
  [PLAT-ARCH-009]  L3 Platform Package Responsibilities — re-export half is
                   subsumed by [PLAT-ARCH-006]; the "L3 functionality" half
                   is a semantic check (which functionality belongs where).
  [PLAT-ARCH-010]  Platform Package Reference — enumerates canonical packages;
                   no per-package violation pattern.
  [PLAT-ARCH-014]  ISA Standard Packages — packages MUST be at L2; no per-
                   package shape check.
  [PLAT-ARCH-020]  L3-Unifier Shadow Pre-Flight Check — pre-flight workflow,
                   verified at author time, not post-facto.
  [PLAT-ARCH-024]  L2 Platform-Extension Pre-Check — pre-flight workflow,
                   same as 020.
  [PLAT-ARCH-028]  Typealiased-Namespace Unifier Collapse — requires symbol-
                   level analysis (no swift-kernel delegate when L3 platform
                   typealiases to Kernel).
  [PLAT-ARCH-030]  L3 POSIX Re-Export or Layer Policy — semantic; whether a
                   given file is "re-export" vs "policy" can't be told from
                   the file contents alone.
  [PLAT-ARCH-031]  Linux Stack Mirrors POSIX — package layer assignment; same
                   structural shape as 001.
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

# POSIX-shared syscalls per IEEE 1003.1, shared by Darwin and Linux. When
# wrapped at the Swift level, they MUST live in swift-iso-9945 per
# [PLAT-ARCH-007]. The list is curated for high-precision detection — only
# names that are unambiguously POSIX-shared appear. Linux-specific
# (epoll_*, io_uring_*) and Darwin-specific (kqueue, mach_*) calls are
# CORRECT in their platform's L2 package and MUST NOT appear here.
POSIX_SHARED_SYSCALLS = (
    # Process control
    "fork", "wait", "waitpid", "execv", "execve", "execvp",
    # Signals
    "signal", "sigaction", "sigprocmask", "kill", "raise", "alarm", "pause",
    # Pipes and sockets
    "pipe", "socket", "socketpair", "bind", "listen", "accept", "connect",
    "send", "sendto", "sendmsg", "recv", "recvfrom", "recvmsg", "shutdown",
    "getsockname", "getpeername", "setsockopt", "getsockopt",
    # Memory mapping
    "mmap", "munmap", "mprotect", "msync", "madvise", "mlock", "munlock",
    # POSIX threads (selected — pthread_* set is large; cover canonical ops)
    "pthread_create", "pthread_join", "pthread_detach", "pthread_self",
    "pthread_mutex_init", "pthread_mutex_lock", "pthread_mutex_unlock",
    "pthread_cond_init", "pthread_cond_wait", "pthread_cond_signal",
)

PLATFORM_IMPORT = re.compile(r"^[ \t]*import[ \t]+(Darwin|Glibc|Musl|WinSDK)\b", re.MULTILINE)
POSIX_IMPORT = re.compile(r"^[ \t]*(?:@[^\s]+\s+)*(?:public[ \t]+|package[ \t]+|internal[ \t]+)?import[ \t]+POSIX_\w+", re.MULTILINE)
PLATFORM_CONDITIONAL = re.compile(r"^\s*#if\s+(os|canImport)\b", re.MULTILINE)
# Match `public enum <Name>` at top level (with optional Sendable conformance).
ROOT_NAMESPACE_RE = {
    "Darwin": re.compile(r"^public[ \t]+enum[ \t]+Darwin\b", re.MULTILINE),
    "Linux": re.compile(r"^public[ \t]+enum[ \t]+Linux\b", re.MULTILINE),
    "Windows": re.compile(r"^public[ \t]+enum[ \t]+Windows\b", re.MULTILINE),
    "ISO_9945": re.compile(r"^public[ \t]+enum[ \t]+ISO_9945\b", re.MULTILINE),
}
# Platform L2 packages → expected root namespace.
L2_ROOT_NAMESPACE = {
    "swift-darwin-standard": "Darwin",
    "swift-linux-standard": "Linux",
    "swift-windows-32": "Windows",
    "swift-windows-standard": "Windows",
    "swift-iso-9945": "ISO_9945",
}
# L3 platform packages → required L2 module-name prefix for the
# `@_exported public import` re-export chain.
L3_RE_EXPORT_PREFIX = {
    "swift-darwin": "Darwin_",
    "swift-linux": "Linux_",
    "swift-windows": "Windows_",
    "swift-posix": "ISO_9945_",
}
EXPORTED_IMPORT_RE = re.compile(
    r"^@_exported[ \t]+public[ \t]+import[ \t]+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
# Bare `(public )?(struct|class|enum) Descriptor` declarations.
DESCRIPTOR_DECL_RE = re.compile(
    r"^[ \t]*(?:public[ \t]+|package[ \t]+|internal[ \t]+|fileprivate[ \t]+|private[ \t]+)?"
    r"(?:struct|class|enum)[ \t]+Descriptor\b",
    re.MULTILINE,
)
PLATFORM_PRIMITIVES_PACKAGES = {
    "swift-darwin-primitives": "Darwin_Primitives_Core",
    "swift-linux-primitives": "Linux_Primitives_Core",
    "swift-windows-primitives": "Windows_Primitives_Core",
}
# A POSIX call is a function name token followed by an open paren. Matches
# the call form (`fork(`, `pipe(`) but not bare references in comments
# unless the comment also contains the paren — vanishingly rare.
POSIX_CALL = re.compile(
    r"\b(" + "|".join(re.escape(s) for s in POSIX_SHARED_SYSCALLS) + r")\s*\("
)


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

    if package_swift.is_file():
        body = package_swift.read_text()
        # [PLAT-ARCH-023] iso-9945 dep direction
        if repo_name == "swift-iso-9945":
            if 'package: "swift-linux-standard"' in body or 'package: "swift-darwin-standard"' in body:
                emit(repo, "PLAT-ARCH-023",
                     "swift-iso-9945 declares dependency on swift-linux-standard or "
                     "swift-darwin-standard (forbidden — iso-9945 is the POSIX-shared base)")
                findings += 1

    # Sources scans
    if sources.is_dir():
        # Build file list. Skip hidden files/dirs (e.g., `.build/`) by
        # checking ONLY the path segments BELOW repo_root — not absolute
        # path segments, which would spuriously match parents like
        # `swift-institute/.github/...` when the validator runs against
        # fixture directories nested under a `.github` parent.
        swift_files: list[Path] = []
        for p in sources.rglob("*.swift"):
            relative = p.relative_to(repo_root)
            if any(seg.startswith(".") for seg in relative.parts):
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

        # [PLAT-ARCH-007] POSIX-shared syscalls in platform-specific L2.
        # If swift-darwin-standard or swift-linux-standard contain a direct
        # call to a POSIX-shared function (fork, pipe, signal, etc.), the
        # wrapper likely belongs in swift-iso-9945 — both Darwin and Linux
        # would otherwise duplicate the POSIX wrapper.
        if repo_name in {"swift-darwin-standard", "swift-linux-standard"}:
            offenders: list[tuple[Path, str]] = []
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                m = POSIX_CALL.search(content)
                if m:
                    offenders.append((f.relative_to(repo_root), m.group(1)))
            if offenders:
                rel, call = offenders[0]
                emit(repo, "PLAT-ARCH-007",
                     f"platform-specific L2 package contains POSIX-shared "
                     f"syscall `{call}(` in {rel} (and {len(offenders) - 1} "
                     f"other file(s) — POSIX-shared wrappers MUST live in "
                     f"swift-iso-9945 per [PLAT-ARCH-007], not be duplicated "
                     f"between Darwin and Linux standards)")
                findings += 1

        # [PLAT-ARCH-004] Platform L2 packages declare platform root namespace.
        expected_root = L2_ROOT_NAMESPACE.get(repo_name)
        if expected_root is not None:
            namespace_re = ROOT_NAMESPACE_RE[expected_root]
            found = False
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                if namespace_re.search(content):
                    found = True
                    break
            if not found:
                emit(repo, "PLAT-ARCH-004",
                     f"L2 spec package MUST declare `public enum {expected_root}` "
                     f"in some source file (per [PLAT-ARCH-004]); no such "
                     f"declaration found under Sources/")
                findings += 1

        # [PLAT-ARCH-005] swift-kernel-primitives MUST NOT declare a concrete
        # `Descriptor` type (struct/class/enum). The L2-canonical Descriptor
        # lives at the spec layer with L3-policy + L3-unifier typealiases.
        if repo_name == "swift-kernel-primitives":
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                if DESCRIPTOR_DECL_RE.search(content):
                    emit(repo, "PLAT-ARCH-005",
                         f"{f.relative_to(repo_root)}: swift-kernel-primitives "
                         f"declares a concrete Descriptor type; per "
                         f"[PLAT-ARCH-005] the L1 layer hosts no Descriptor — "
                         f"the L2-canonical type lives at the spec layer with "
                         f"typealias unification at L3-policy + L3-unifier")
                    findings += 1
                    break

        # [PLAT-ARCH-006] L3 platform packages re-export their L2 spec layer.
        required_prefix = L3_RE_EXPORT_PREFIX.get(repo_name)
        if required_prefix is not None:
            found = False
            for f in swift_files:
                try:
                    content = f.read_text()
                except Exception:
                    continue
                for m in EXPORTED_IMPORT_RE.finditer(content):
                    module = m.group(1)
                    if module.startswith(required_prefix):
                        found = True
                        break
                if found:
                    break
            if not found:
                emit(repo, "PLAT-ARCH-006",
                     f"L3 platform package MUST `@_exported public import` at "
                     f"least one module from its L2 spec layer (expected "
                     f"module name prefix `{required_prefix}` per "
                     f"[PLAT-ARCH-006]); no such re-export found under Sources/")
                findings += 1

        # [PLAT-ARCH-027] Platform-primitives variant targets re-export Core.
        required_core = PLATFORM_PRIMITIVES_PACKAGES.get(repo_name)
        if required_core is not None:
            # Each direct subdirectory of Sources/ that is not Core is a
            # variant target. Its Exports.swift / exports.swift MUST contain
            # an `@_exported public import <required_core>` line.
            for variant_dir in sorted(p for p in sources.iterdir() if p.is_dir()):
                vname = variant_dir.name
                # Skip the Core target itself (it declares the namespace).
                if vname.endswith(" Core") or vname.endswith("_Core") or vname == "Core":
                    continue
                # Look for an exports file at the variant root.
                exports_candidates = [
                    variant_dir / "Exports.swift",
                    variant_dir / "exports.swift",
                ]
                exports_file = next((c for c in exports_candidates if c.is_file()), None)
                if exports_file is None:
                    emit(repo, "PLAT-ARCH-027",
                         f"{variant_dir.name}: variant target has no "
                         f"Exports.swift / exports.swift — per [PLAT-ARCH-027] "
                         f"each variant MUST re-export `{required_core}` so "
                         f"the platform root namespace flows without "
                         f"publishing Core")
                    findings += 1
                    continue
                try:
                    content = exports_file.read_text()
                except Exception:
                    continue
                modules = [m.group(1) for m in EXPORTED_IMPORT_RE.finditer(content)]
                if required_core not in modules:
                    emit(repo, "PLAT-ARCH-027",
                         f"{exports_file.relative_to(repo_root)}: missing "
                         f"`@_exported public import {required_core}` — variant "
                         f"target MUST re-export Core per [PLAT-ARCH-027]")
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
