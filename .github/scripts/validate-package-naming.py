#!/usr/bin/env python3
"""validate-package-naming.py — org-scoped package repo-naming rules.

Naming-cluster host script (mirrors the validate-file-naming.py precedent:
related naming rules share one script). Rules checked (v1):

  [PRIM-NAME-001]  Every PACKAGE repo in the swift-primitives org MUST use
                   the `-primitives` suffix. Non-package repos (no
                   Package.swift — Research, Scripts, xcworkspaces, org
                   sites) are out of scope.
  [PKG-NAME-014]   Org-prefix on pack-targets: a package MUST NOT declare a
                   non-test target whose name collides with a target of a
                   DIRECT dependency (SwiftPM rejects duplicate module names,
                   but only at a consumer's compile time — this is the
                   authoring-time pre-check). Dep manifests resolve via path
                   deps on disk and url deps against the local org mirrors;
                   deps without a local manifest are skipped. Direct deps
                   only in v1 (the canonical layered-vocabulary instance is
                   a direct edge).
  [PKG-NAME-017]   L1 name mirrors the shipped surface: when a primitives-org
                   package has a detectable root (files named
                   `X[.Y].Protocol.swift` / `X[.Y].Witness.swift` under
                   Sources/ — the greppable root-existence test the rule
                   itself names), the repo name MUST be
                   `swift-<kebab(root-path)>-primitives` for at least one
                   detected root stem. Packages with no detectable root use
                   the family-label register (judgment) and are skipped.
  [MOD-023]        `#externalMacro(module:)` MUST cite the SwiftPM-normalized
                   module name (spaces → underscores), not the collapsed or
                   as-written target name. Target names come from
                   `swift package dump-package` (resolves constant-named
                   targets the manifest regex cannot see); only near-misses
                   of the package's OWN macro targets fire — cites of
                   external packages' macro modules pass through. The
                   dump-package call is gated on `#externalMacro` actually
                   appearing in Sources/, so non-macro packages stay fast.

Org derivation: the `<repo-name>` argument's owner part. Harness fixtures
(owner `swift-institute-test/` per tests/run.sh) encode the intended org in
the scenario dir name via a double-underscore: `swift-primitives__swift-foo`
is checked as org swift-primitives, repo swift-foo (pilot-10 fixture
carve-out pattern).

Output: TSV findings `repo<TAB>PRIM-NAME-001<TAB>message` (validate_lib.emit).

Usage:
  validate-package-naming.py <repo-name> <repo-root>

Provenance: REPORT-corpus-review.md §5 NONE batch, promoted via /promote-rule
per HANDOFF-mechanization-arc W1. Outcome record:
swift-institute/Audits/PROMOTE-PRIM-NAME-001-2026-07-06.md.
"""
from __future__ import annotations

import sys
from pathlib import Path

import json
import os
import re
import subprocess

from validate_lib import emit

RULE = "PRIM-NAME-001"
RULE_COLLISION = "PKG-NAME-014"
RULE_MACRO = "MOD-023"
FIXTURE_OWNER = "swift-institute-test"

# [PRIM-NAME-001] sanctioned exceptions (principal ruling 2026-07-06, recorded
# in Audits/PROMOTE-PRIM-NAME-001-2026-07-06.md): org-scoped infrastructure
# whose established name is itself a deliberate convention —
#   swift-primitives-linter-rules: the cross-tier `-linter-rules` family
#     ([PKG-NAME-014] canonical table);
#   swift-standard-library-extensions: descriptive substrate; no conforming
#     name improves on it (must sit at L1 — its consumers are L1).
PRIM_NAME_EXEMPT = frozenset({
    "swift-primitives-linter-rules",
    "swift-standard-library-extensions",
})

RE_EXTERNAL_MACRO = re.compile(r'#externalMacro\s*\(\s*module:\s*"([^"]+)"')
MACRO_SKIP_DIRS = {".build", ".git", ".swiftpm", ".claude", "node_modules",
                   "checkouts"}


def external_macro_cites(root: Path) -> list[tuple[Path, int, str]]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root / "Sources"):
        dirnames[:] = [d for d in dirnames if d not in MACRO_SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            p = Path(dirpath) / fn
            for i, line in enumerate(p.read_text(encoding="utf-8",
                                                 errors="replace").splitlines(), 1):
                m = RE_EXTERNAL_MACRO.search(line)
                if m:
                    out.append((p.relative_to(root), i, m.group(1)))
    return out


def macro_target_names(root: Path) -> set[str] | None:
    """Macro-type target names via dump-package (resolves constant-named
    targets). None on dump failure — callers skip the check (environment
    defect, not a finding)."""
    try:
        proc = subprocess.run(
            ["swift", "package", "dump-package", "--package-path", str(root)],
            capture_output=True, text=True, timeout=180)
    except (subprocess.SubprocessError, OSError):
        return None
    if proc.returncode != 0:
        return None
    manifest = json.loads(proc.stdout)
    return {t.get("name", "") for t in manifest.get("targets", [])
            if t.get("type") == "macro"}


def squash(name: str) -> str:
    return name.replace(" ", "").replace("_", "").lower()


RULE_MIRROR = "PKG-NAME-017"


def kebab(namespace_path: str) -> str:
    """`Buffer.Linear` → `buffer-linear`; camel humps split (`TernaryLogic`
    → `ternary-logic`)."""
    parts = []
    for seg in namespace_path.split("."):
        parts.extend(re.findall(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+", seg))
    return "-".join(p.lower() for p in parts if p)


def root_stems(root: Path) -> set[str]:
    """Namespace paths of shipped roots, per the rule's greppable test:
    file names `X[.Y].Protocol.swift` / `X[.Y].Witness.swift` under Sources/."""
    stems = set()
    src = root / "Sources"
    if not src.is_dir():
        return stems
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if d not in MACRO_SKIP_DIRS]
        for fn in filenames:
            m = re.match(r"^(.+)\.(Protocol|Witness)\.swift$", fn)
            # `A+B.Protocol.swift` is a CONFORMANCE file ([API-IMPL-007]'s
            # `+` convention — A adopting B's protocol), not a root
            # declaration; only plain `X[.Y].Protocol.swift` marks a root.
            if m and "+" not in m.group(1):
                stems.add(m.group(1))
    return stems

RE_TARGET = re.compile(
    r'\.(?:target|executableTarget|macro)\s*\(\s*name:\s*"([^"]+)"')
RE_URL_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?url:\s*"([^"]+)"')
RE_PATH_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"([^"]+)"')


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def non_test_targets(manifest_text: str) -> set[str]:
    return set(RE_TARGET.findall(strip_comments(manifest_text)))


def dep_manifest_paths(manifest_text: str, root: Path) -> dict[str, Path]:
    """{dep-name → local Package.swift path} for direct deps resolvable on
    this machine (path deps; url deps whose repo exists in an org mirror
    two levels up from the host root)."""
    text = strip_comments(manifest_text)
    out: dict[str, Path] = {}
    for rel in RE_PATH_DEP.findall(text):
        d = (root / rel).resolve()
        if (d / "Package.swift").is_file():
            out[d.name] = d / "Package.swift"
    dev = root.resolve().parent.parent
    for url in RE_URL_DEP.findall(text):
        parts = url.rstrip("/").split("/")
        if len(parts) < 2:
            continue
        name = parts[-1][:-4] if parts[-1].endswith(".git") else parts[-1]
        candidate = dev / parts[-2] / name / "Package.swift"
        if candidate.is_file():
            out[name] = candidate
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])
    if not root.is_dir():
        print(f"# error: repo root not found: {root}", file=sys.stderr)
        return 2

    owner, _, name = repo.rpartition("/")
    if owner == FIXTURE_OWNER and "__" in name:
        owner, _, name = name.partition("__")

    if not (root / "Package.swift").is_file():
        return 0  # non-package repo (Research, Scripts, org site, workspace)

    # [PRIM-NAME-001] — primitives-org repo suffix.
    if (owner == "swift-primitives" and not name.endswith("-primitives")
            and name not in PRIM_NAME_EXEMPT):
        emit(repo, RULE,
             f"package repo '{name}' in the swift-primitives org lacks the "
             f"'-primitives' suffix ([PRIM-NAME-001]); rename the repo or "
             f"record a principal-sanctioned exception in the outcome record")

    # [PKG-NAME-014] — target-name collisions with direct deps.
    manifest_text = (root / "Package.swift").read_text(encoding="utf-8",
                                                       errors="replace")
    own = non_test_targets(manifest_text)
    if own:
        for dep_name, dep_manifest in sorted(
                dep_manifest_paths(manifest_text, root).items()):
            dep_targets = non_test_targets(
                dep_manifest.read_text(encoding="utf-8", errors="replace"))
            for clash in sorted(own & dep_targets):
                emit(repo, RULE_COLLISION,
                     f"target '{clash}' collides with a target of direct "
                     f"dependency '{dep_name}' — SwiftPM rejects duplicate "
                     f"module names at consumer compile time; prefix the "
                     f"pack-target per [PKG-NAME-014]")

    # [PKG-NAME-017] — L1 name mirrors the shipped surface (root register).
    if (owner == "swift-primitives" and name.endswith("-primitives")
            and name.startswith("swift-")):
        middle = name[len("swift-"):-len("-primitives")]
        stems = root_stems(root)
        # The name mirrors the package-ROOT namespace path; a Protocol file
        # may live in a deeper sub-namespace (Render.Async.Sink under
        # swift-render-async-primitives), so an ancestor-path match conforms.
        def mirrors(stem: str) -> bool:
            k = kebab(stem)
            return k == middle or k.startswith(middle + "-")
        if stems and not any(mirrors(s) for s in stems):
            shown = ", ".join(sorted(stems)[:4])
            emit(repo, RULE_MIRROR,
                 f"repo name 'swift-{middle}-primitives' mirrors none of the "
                 f"shipped root namespace(s) [{shown}] ([PKG-NAME-017]: L1 "
                 f"names are the layer-affixed kebab of the surface; "
                 f"family-label register applies only in a root vacuum)")

    # [MOD-023] — #externalMacro module-name normalization.
    cites = external_macro_cites(root) if (root / "Sources").is_dir() else []
    if cites:
        macros = macro_target_names(root)
        if macros:
            normalized = {m.replace(" ", "_") for m in macros}
            by_squash = {squash(m): m for m in macros}
            for rel, lineno, cited in cites:
                if cited in normalized:
                    continue
                target = by_squash.get(squash(cited))
                if target is None:
                    continue  # cites an external package's macro module
                emit(repo, RULE_MACRO,
                     f"{rel}:{lineno}: #externalMacro(module: \"{cited}\") does "
                     f"not match the SwiftPM-normalized module name "
                     f"'{target.replace(' ', '_')}' of macro target '{target}' "
                     f"([MOD-023]: spaces normalize to underscores)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
