#!/usr/bin/env python3
"""validate-package-shape.py — verify Swift package shape conventions.

Wave 2 mechanization (2026-05-11) — companion to validate-package-shape.yml.

Rules checked (v1):
  [PATTERN-001]  C shim targets MUST use independent per-platform headers,
                 NOT a shared header with `#if defined(__APPLE__) / __linux__`
                 conditional multiplexing. Detection: any `*.h` file under
                 Sources/ that contains BOTH `__APPLE__` and `__linux__` /
                 `__LINUX__` C-preprocessor checks.
  [PATTERN-003]  Best-effort check: when `Tests/Package.swift` exists, the
                 nested test package pattern is in use; this validator flags
                 obvious structural defects (file is empty, lacks the
                 `swift-tools-version` line, or has no `.testTarget`).
  [PATTERN-004]  Platform-specific package dependencies MUST use
                 `condition: .when(platforms:)`. Detection: every
                 `.product(name:..., package: "<platform-pkg>")` reference
                 in Package.swift MUST appear in a call that also contains
                 `condition: .when(platforms:`. Platform packages: swift-darwin*,
                 swift-linux*, swift-windows*, swift-iso-9945, swift-posix.
  [PATTERN-004c] `.linkedLibrary("<name>")` declarations MUST include a
                 `.when(platforms:` argument in the same call when the
                 library is not always-linked (we can't tell from the file
                 which libraries are always-linked, so we require the
                 explicit `.when` on every `.linkedLibrary` for safety).
  [PATTERN-005]  All packages MUST require Swift 6.3+ tools version AND
                 declare `swiftLanguageModes: [.v6]`. (Moved from
                 validate-platform-architecture.py per Wave 2 consolidation.)
  [PATTERN-006]  Packages SHOULD enable upcoming features `ExistentialAny`,
                 `InternalImportsByDefault`, `MemberImportVisibility`.
                 (Moved from validate-platform-architecture.py per Wave 2
                 consolidation.)

Wave 4 extensions (2026-05-11):
  [PATTERN-004b] Module name normalization. Swift normalizes Package.swift
                 target names by replacing spaces with underscores. Target
                 names MUST NOT mix the two conventions — a target name
                 containing BOTH a space AND an underscore is flagged
                 (e.g., `"Real_Primitives Core"` is mixed). Pure
                 spec-namespace forms (`"RFC_4122"`, `"ISO_9945"`) and
                 pure space-separated forms (`"Real Primitives"`) are
                 acceptable.
  [PATTERN-022]  `~Copyable` nested types MUST live in separate files.
                 Mechanical narrow check: a Sources/*.swift file whose
                 top-level declaration declares a generic type with a
                 `~Copyable` constraint AND whose body contains nested
                 `struct`/`class`/`enum`/`actor` type declarations is
                 flagged. The fix is `extension Parent where ...
                 ~Copyable { type ... }` in a separate file.

Rules NOT yet mechanized (documented for traceability):
  [PATTERN-007]  Experimental feature flags are permissive (MAY). No
                 mechanical violation pattern exists; consumer audits cover
                 the case-by-case applicability.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

# Platform-specific packages: deps on these MUST appear in a `.product(...)`
# call that also contains `condition: .when(platforms:`. The set is the
# package names commonly referenced by name across the ecosystem; a longer
# list would not change detection precision (the regex matches the package:
# argument string verbatim).
PLATFORM_PACKAGES = (
    "swift-darwin",
    "swift-darwin-standard",
    "swift-darwin-primitives",
    "swift-linux",
    "swift-linux-standard",
    "swift-linux-primitives",
    "swift-linux-foundation",
    "swift-windows",
    "swift-windows-32",
    "swift-windows-standard",
    "swift-windows-primitives",
    "swift-iso-9945",
    "swift-posix",
)

REQUIRED_TOOLS_VERSION = re.compile(r"^// swift-tools-version:\s*([0-9.]+)")
LANG_MODE_V6 = re.compile(r"swiftLanguageModes:\s*\[\s*\.v6\s*\]")
UPCOMING_FEATURES = ("ExistentialAny", "InternalImportsByDefault", "MemberImportVisibility")
LINKED_LIBRARY = re.compile(r"\.linkedLibrary\(([^)]*)\)")
PRODUCT_DEP = re.compile(
    r'\.product\(\s*name:\s*"[^"]+"\s*,\s*package:\s*"([^"]+)"([^)]*)\)',
    re.DOTALL,
)
HEADER_APPLE = re.compile(r"\bdefined\s*\(\s*__APPLE__\s*\)")
HEADER_LINUX = re.compile(r"\bdefined\s*\(\s*__(?:linux|LINUX)__\s*\)")
# Match `.target(name: "...")`, `.library(name: "...")`, `.executable(name: "...")`,
# `.testTarget(name: "...")`, `.product(name: "...")`. Captures the string.
TARGET_NAME = re.compile(
    r'\.(?:target|library|executable|testTarget|product)\(\s*name:\s*"([^"]+)"'
)
# Match a top-level generic struct/class/enum/actor whose generic parameter
# clause contains `~Copyable`. Captures the type name and an approximate
# brace body for nested-type detection.
COPYABLE_PARENT = re.compile(
    r"^(?:public\s+|internal\s+|fileprivate\s+|private\s+|package\s+)?"
    r"(?:struct|class|enum|actor)\s+(\w+)\s*<[^>]*~Copyable[^>]*>",
    re.MULTILINE,
)
NESTED_TYPE_DECL = re.compile(
    r"^\s+(?:public\s+|internal\s+|fileprivate\s+|private\s+|package\s+)?"
    r"(?:struct|class|enum|actor)\s+\w+",
    re.MULTILINE,
)


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def iter_swift_files(sources: Path, repo_root: Path):
    """Yield Swift source files under `sources` excluding dot-prefixed parts
    (e.g., `.build/`) below `repo_root`.
    """
    if not sources.is_dir():
        return
    for p in sources.rglob("*.swift"):
        relative = p.relative_to(repo_root)
        if any(seg.startswith(".") for seg in relative.parts):
            continue
        yield p


def iter_header_files(sources: Path, repo_root: Path):
    """Yield C header files under `sources` excluding dot-prefixed parts.

    Sorted to keep validator output deterministic across runs.
    """
    if not sources.is_dir():
        return
    paths: list[Path] = []
    for p in sources.rglob("*.h"):
        relative = p.relative_to(repo_root)
        if any(seg.startswith(".") for seg in relative.parts):
            continue
        paths.append(p)
    paths.sort()
    yield from paths


def check_pattern_005_006(repo: str, package_swift: Path) -> int:
    """Swift 6.3+ tools version, .v6 lang mode, three upcoming features."""
    findings = 0
    if not package_swift.is_file():
        return 0
    body = package_swift.read_text()
    lines = body.splitlines()
    if lines:
        m = REQUIRED_TOOLS_VERSION.match(lines[0])
        if not m:
            emit(repo, "PATTERN-005",
                 "Package.swift first line not `// swift-tools-version: X.Y[.Z]`")
            findings += 1
        else:
            version = m.group(1)
            parts = [int(x) for x in version.split(".")]
            if parts < [6, 3]:
                emit(repo, "PATTERN-005",
                     f"Package.swift swift-tools-version is {version}; required ≥ 6.3")
                findings += 1
    if not LANG_MODE_V6.search(body):
        emit(repo, "PATTERN-005",
             "Package.swift missing `swiftLanguageModes: [.v6]` declaration")
        findings += 1
    for feat in UPCOMING_FEATURES:
        if f'enableUpcomingFeature("{feat}")' not in body:
            emit(repo, "PATTERN-006",
                 f"Package.swift does not enableUpcomingFeature({feat!r}) "
                 f"(SHOULD per [PATTERN-006])")
            findings += 1
    return findings


def is_platform_specific_repo(repo_name: str) -> bool:
    """Return True for packages whose name marks them as single-platform.

    Their deps are inherently single-platform — adding `.when(platforms:)`
    would be redundant noise. The rule [PATTERN-004] targets cross-platform
    packages that conditionally depend on platform-specific siblings.
    """
    return (
        repo_name.startswith("swift-darwin")
        or repo_name.startswith("swift-linux")
        or repo_name.startswith("swift-windows")
        or repo_name == "swift-posix"
        or repo_name == "swift-iso-9945"
    )


def check_pattern_004(repo: str, package_swift: Path) -> int:
    """Platform-specific package deps MUST use `condition: .when(platforms:`.

    Skipped for platform-specific packages (their deps are inherently
    single-platform; no `.when` needed).
    """
    if not package_swift.is_file():
        return 0
    repo_name = repo.split("/")[-1]
    if is_platform_specific_repo(repo_name):
        return 0
    body = package_swift.read_text()
    findings = 0
    for m in PRODUCT_DEP.finditer(body):
        pkg = m.group(1)
        tail = m.group(2)
        if pkg not in PLATFORM_PACKAGES:
            continue
        if ".when(platforms:" not in tail:
            emit(repo, "PATTERN-004",
                 f"Package.swift `.product(package: {pkg!r})` lacks "
                 f"`condition: .when(platforms:` — platform-specific deps "
                 f"MUST be conditional per [PATTERN-004]")
            findings += 1
    return findings


def check_pattern_004c(repo: str, package_swift: Path) -> int:
    """`.linkedLibrary(...)` MUST include `.when(platforms:`."""
    if not package_swift.is_file():
        return 0
    body = package_swift.read_text()
    findings = 0
    for m in LINKED_LIBRARY.finditer(body):
        args = m.group(1)
        if ".when(platforms:" not in args:
            # Try to extract the library name for the message.
            name_match = re.search(r'"([^"]+)"', args)
            name = name_match.group(1) if name_match else "<unknown>"
            emit(repo, "PATTERN-004c",
                 f"Package.swift `.linkedLibrary({name!r})` lacks "
                 f"`.when(platforms:` argument — linker flags MUST be "
                 f"platform-conditional per [PATTERN-004c]")
            findings += 1
    return findings


def check_pattern_001(repo: str, sources: Path, repo_root: Path) -> int:
    """C shim headers MUST NOT multiplex platforms via `#if defined(...)`."""
    findings = 0
    for h in iter_header_files(sources, repo_root):
        try:
            content = h.read_text(errors="replace")
        except Exception:
            continue
        if HEADER_APPLE.search(content) and HEADER_LINUX.search(content):
            emit(repo, "PATTERN-001",
                 f"{h.relative_to(repo_root)}: C header multiplexes platforms "
                 f"via `__APPLE__` and `__linux__` preprocessor checks; "
                 f"per [PATTERN-001] each platform's shim MUST be an "
                 f"independent file (no shared conditional header)")
            findings += 1
    return findings


def check_pattern_003(repo: str, repo_root: Path) -> int:
    """When `Tests/Package.swift` exists, validate basic nested-test shape."""
    nested = repo_root / "Tests" / "Package.swift"
    if not nested.is_file():
        return 0
    findings = 0
    try:
        body = nested.read_text()
    except Exception:
        return 0
    if not body.strip():
        emit(repo, "PATTERN-003",
             "Tests/Package.swift exists but is empty — nested test package "
             "MUST be a valid Swift package per [PATTERN-003]")
        return 1
    if not REQUIRED_TOOLS_VERSION.match(body.splitlines()[0] if body.splitlines() else ""):
        emit(repo, "PATTERN-003",
             "Tests/Package.swift first line not `// swift-tools-version: X.Y[.Z]` "
             "— nested test package MUST be a valid Swift package per [PATTERN-003]")
        findings += 1
    if ".testTarget(" not in body:
        emit(repo, "PATTERN-003",
             "Tests/Package.swift declares no `.testTarget(...)` — nested test "
             "package SHOULD expose at least one test target per [PATTERN-003]")
        findings += 1
    return findings


def check_pattern_004b(repo: str, package_swift: Path) -> int:
    """SwiftPM target name normalization — names MUST NOT mix space + underscore.

    Swift maps spaces in target names to underscores in import identifiers;
    using both in the same name is double-encoding (e.g., `"Real_Primitives
    Core"`). Pure space-separated (`"Real Primitives"`) and pure spec-
    namespace underscore (`"RFC_4122"`) forms are acceptable.
    """
    if not package_swift.is_file():
        return 0
    body = package_swift.read_text()
    findings = 0
    seen: set[str] = set()
    for m in TARGET_NAME.finditer(body):
        name = m.group(1)
        if name in seen:
            continue
        seen.add(name)
        if "_" in name and " " in name:
            emit(repo, "PATTERN-004b",
                 f"Package.swift target name {name!r} mixes spaces and "
                 f"underscores; Swift normalizes spaces to underscores "
                 f"in import identifiers — use either pure spaces "
                 f"(`\"Foo Bar\"`) or a pure spec-namespace form "
                 f"(`\"RFC_4122\"`) per [PATTERN-004b]")
            findings += 1
    return findings


def check_pattern_022(repo: str, sources: Path, repo_root: Path) -> int:
    """`~Copyable` nested types MUST live in separate files.

    Narrow mechanical check: a `.swift` file under Sources/ whose top-level
    type declaration carries a `~Copyable` constraint AND whose body
    contains nested `struct`/`class`/`enum`/`actor` declarations.
    """
    findings = 0
    for f in iter_swift_files(sources, repo_root):
        relative = f.relative_to(repo_root)
        if any(seg in {"Tests", "Experiments", "Examples", "Benchmarks"}
               for seg in relative.parts):
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        parent_match = COPYABLE_PARENT.search(text)
        if parent_match is None:
            continue
        # Approximate the parent's brace body: from the parent decl's
        # opening brace to a top-level closing brace.
        decl_start = parent_match.end()
        brace = text.find("{", decl_start)
        if brace == -1:
            continue
        depth = 1
        i = brace + 1
        while i < len(text) and depth > 0:
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        body_block = text[brace + 1:i - 1] if depth == 0 else text[brace + 1:]
        if NESTED_TYPE_DECL.search(body_block):
            emit(repo, "PATTERN-022",
                 f"{relative}: declares `~Copyable` generic type "
                 f"`{parent_match.group(1)}` AND contains nested type "
                 f"declarations in its body; nested types under `~Copyable` "
                 f"parents MUST be hoisted into separate files via "
                 f"`extension Parent where Element: ~Copyable {{ ... }}` "
                 f"per [PATTERN-022]")
            findings += 1
    return findings


def validate_package_shape(repo: str, repo_root: Path) -> int:
    findings = 0
    package_swift = repo_root / "Package.swift"
    sources = repo_root / "Sources"

    findings += check_pattern_005_006(repo, package_swift)
    findings += check_pattern_004(repo, package_swift)
    findings += check_pattern_004b(repo, package_swift)
    findings += check_pattern_004c(repo, package_swift)
    findings += check_pattern_001(repo, sources, repo_root)
    findings += check_pattern_003(repo, repo_root)
    findings += check_pattern_022(repo, sources, repo_root)

    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: validate-package-shape.py <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo = argv[1]
    repo_root = Path(argv[2])
    findings = validate_package_shape(repo, repo_root)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
