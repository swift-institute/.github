#!/usr/bin/env python3
"""validate-target-imports.py — [MOD-038] every source import is a declared edge.

Rule checked: [MOD-038] — every module a target's sources `import` (any
form) MUST appear in that target's `dependencies:` in Package.swift, as a
same-package target dependency or a cross-package product dependency.
Excepted: the target's own module and toolchain/SDK-supplied modules. An
import satisfied only transitively is an undeclared build edge — whether the
target compiles becomes a build-plan scheduling race (the W3-F2 incident:
nondeterministic `no such module` surfacing in a DOWNSTREAM consumer's gate).

Detection (the rule's queued D3 disposition anticipated exactly this shape):
  1. `swift package dump-package` → targets (name, type, path) + declared
     per-target dependencies (target / product / byName forms).
  2. Per non-plugin target: source dir = explicit `path` or the SwiftPM
     default (`Sources/<name>`, `Tests/<name>`); imports = the first dotted
     component of every `import` statement (scoped/attributed forms included;
     fenced by line grammar, comments stripped).
  3. Allowed set = own module ∪ same-package target deps (normalized names)
     ∪ declared product deps' member modules (dep manifests resolved locally:
     path deps on disk, url deps via the org mirrors — same resolution as
     validate-package-naming) ∪ the toolchain set below. byName deps resolve
     to a same-package target first, else to a like-named product of any
     declared dep.
  4. Anything else imported = an undeclared edge → finding.

Unresolvable dep manifests degrade soft: their products' member modules are
unknown, so any import that MIGHT come from them is skipped (no finding) —
the checker under-reports rather than false-fires when a dep isn't on disk.

Output: TSV `repo<TAB>MOD-038<TAB>message` (validate_lib.emit).

Usage:
  validate-target-imports.py <repo-name> <repo-root>

Provenance: REPORT-corpus-review.md §5 SPEC'D batch, promoted via
/promote-rule per HANDOFF-mechanization-arc W1. Outcome record:
swift-institute/Audits/PROMOTE-MOD-038-2026-07-06.md.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from validate_lib import emit

RULE = "MOD-038"

SKIP_DIRS = {".build", ".git", ".swiftpm", ".claude", "node_modules", "checkouts"}

# Toolchain/SDK-supplied modules (the rule's carve): stdlib + testing +
# platform + compiler-shipped support modules. Extend with provenance when a
# false positive names a genuinely toolchain-shipped module.
TOOLCHAIN_MODULES = {
    "Swift", "Testing", "XCTest", "Foundation", "FoundationEssentials",
    "Dispatch", "os", "Darwin", "Glibc", "Musl", "WinSDK", "Android",
    "Observation", "Synchronization", "Builtin", "CRT", "ucrt",
    "SwiftShims", "DistributedActors", "Distributed", "RegexBuilder",
    "StringProcessing", "CoreFoundation", "ObjectiveC", "simd", "Accelerate",
}

RE_IMPORT = re.compile(
    r"^\s*(?:@[\w()_]+\s+)*"
    r"(?:public\s+|package\s+|internal\s+|fileprivate\s+|private\s+)?"
    r"import\s+"
    r"(?:struct\s+|class\s+|enum\s+|protocol\s+|typealias\s+|func\s+|var\s+|let\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)")
RE_URL_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?url:\s*"([^"]+)"')
RE_PATH_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"([^"]+)"')
RE_PRODUCT_DECL = re.compile(
    r'\.library\s*\(\s*name:\s*"([^"]+)"[^)]*?targets:\s*\[([^\]]*)\]', re.S)
RE_TARGET_DECL = re.compile(
    r'\.(?:target|executableTarget|macro)\s*\(\s*name:\s*"([^"]+)"')


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def normalize(name: str) -> str:
    return name.replace(" ", "_").replace("-", "_")


def dump(root: Path) -> dict | None:
    try:
        proc = subprocess.run(
            ["swift", "package", "dump-package", "--package-path", str(root)],
            capture_output=True, text=True, timeout=180)
    except (subprocess.SubprocessError, OSError):
        return None
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout)


def dep_products(manifest_text: str) -> dict[str, set[str]]:
    """{product-name → member module names} from a dependency's manifest."""
    text = strip_comments(manifest_text)
    out: dict[str, set[str]] = {}
    for name, targets_blob in RE_PRODUCT_DECL.findall(text):
        members = set(re.findall(r'"([^"]+)"', targets_blob))
        out[name] = {normalize(m) for m in members}
    return out


def local_dep_manifests(manifest_text: str, root: Path) -> dict[str, Path]:
    text = strip_comments(manifest_text)
    out: dict[str, Path] = {}
    for rel in RE_PATH_DEP.findall(text):
        d = (root / rel).resolve()
        if (d / "Package.swift").is_file():
            out[d.name.lower()] = d / "Package.swift"
    dev = root.resolve().parent.parent
    for url in RE_URL_DEP.findall(text):
        parts = url.rstrip("/").split("/")
        if len(parts) < 2:
            continue
        name = parts[-1][:-4] if parts[-1].endswith(".git") else parts[-1]
        candidate = dev / parts[-2] / name / "Package.swift"
        if candidate.is_file():
            out[name.lower()] = candidate
    return out


def imports_of(source_dir: Path) -> dict[str, tuple[str, int]]:
    """{module → (rel-file, line)} — first sighting of each imported module."""
    out: dict[str, tuple[str, int]] = {}
    for dirpath, dirnames, filenames in os.walk(source_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            p = Path(dirpath) / fn
            text = strip_comments(p.read_text(encoding="utf-8", errors="replace"))
            for i, line in enumerate(text.splitlines(), 1):
                m = RE_IMPORT.match(line)
                if m and m.group(1) not in out:
                    out[m.group(1)] = (str(p.relative_to(source_dir.parent.parent)), i)
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])
    if not (root / "Package.swift").is_file():
        return 0
    manifest = dump(root)
    if manifest is None:
        print(f"# error: dump-package failed for {root}", file=sys.stderr)
        return 2
    manifest_text = (root / "Package.swift").read_text(encoding="utf-8",
                                                       errors="replace")
    dep_manifest_paths = local_dep_manifests(manifest_text, root)
    dep_product_cache: dict[str, dict[str, set[str]]] = {}

    def products_of(dep_key: str) -> dict[str, set[str]]:
        if dep_key not in dep_product_cache:
            path = dep_manifest_paths.get(dep_key)
            dep_product_cache[dep_key] = (
                dep_products(path.read_text(encoding="utf-8", errors="replace"))
                if path else {})
        return dep_product_cache[dep_key]

    all_dep_products: dict[str, set[str]] = {}
    unresolvable_deps = False
    declared_dep_keys = set(dep_manifest_paths)
    # Deps not resolvable locally → soft mode (under-report).
    declared_in_manifest = set(RE_URL_DEP.findall(strip_comments(manifest_text))) \
        | set(RE_PATH_DEP.findall(strip_comments(manifest_text)))
    if len(declared_in_manifest) > len(dep_manifest_paths):
        unresolvable_deps = True
    for key in declared_dep_keys:
        for prod, modules in products_of(key).items():
            all_dep_products.setdefault(prod, set()).update(modules)

    same_package_targets = {t.get("name", "") for t in manifest.get("targets", [])}

    for target in manifest.get("targets", []):
        ttype = target.get("type")
        if ttype in ("plugin", "binary", "system"):
            continue
        name = target.get("name", "")
        if target.get("path"):
            src = root / target["path"]
        else:
            base = "Tests" if ttype == "test" else "Sources"
            src = root / base / name
        if not src.is_dir():
            continue

        allowed = {normalize(name)}
        for dep in target.get("dependencies", []):
            for kind, val in dep.items():
                dep_name = val[0] if isinstance(val, list) and val else None
                if not dep_name:
                    continue
                if kind == "target" or (kind == "byName"
                                        and dep_name in same_package_targets):
                    allowed.add(normalize(dep_name))
                elif kind == "product":
                    allowed |= all_dep_products.get(dep_name, set())
                    if dep_name not in all_dep_products:
                        allowed.add(normalize(dep_name))  # unresolved: soft
                elif kind == "byName":
                    allowed |= all_dep_products.get(dep_name, set())
                    allowed.add(normalize(dep_name))

        for module, (rel, line) in sorted(imports_of(src).items()):
            if module in TOOLCHAIN_MODULES or module.startswith("_"):
                continue
            if module in allowed:
                continue
            if unresolvable_deps:
                continue  # soft mode: a non-local dep might supply it
            emit(repo, RULE,
                 f"{rel}:{line}: target '{name}' imports '{module}' without a "
                 f"declared dependency edge ([MOD-038]: transitive-build riding "
                 f"is a scheduling race; declare the target/product dependency)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
