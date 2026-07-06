#!/usr/bin/env python3
"""validate-test-target-layers.py — [ARCH-LAYER-012] test-target layer check.

Rule checked: [ARCH-LAYER-012] — the five-layer upward-dependency prohibition
applies to test targets too. Tests share the package's Package.swift, so a
test target MUST NOT declare a dependency on a package ABOVE the host
package's layer (e.g. an L2 `swift-*-standard`'s tests depending on the L3
`swift-json`). The layer position is the package's, not the target's.

Detection (manifest check over `swift package dump-package` JSON, per the
seat-approved spec — HANDOFF-meta-ecosystem-followups §1(e)):
  1. Dump the host manifest; derive the host layer from the repo name.
  2. For each `.testTarget`, resolve `product`-kind dependencies to their
     owning package identity; map identity → layer:
       `*-primitives` → L1;
       spec-authority prefixes (`swift-rfc-*`, `swift-iso-*`, `swift-ietf-*`,
       `swift-ieee-*`, `swift-w3c-*`, `swift-whatwg-*`, `swift-ecma-*`,
       `swift-incits-*`, `swift-iec-*`) or the `-standard` convergence
       suffix → L2;
       other `swift-*` → L3.
     `byName`/`target` dependencies resolve within the package (no layer
     edge) and are skipped; unknown identities are skipped. External
     (non-institute-org) packages carry no institute layer and are exempt —
     the org is read from the dependency's sourceControl/fileSystem location
     (remote URL org, or the parent dir of a mirror-intercepted local path).
  3. Flag any test-target dep STRICTLY ABOVE the host layer. (The staged
     spec said "at/above"; the owning rule's Statement is upward-only —
     same-layer discipline is [PRIM-ARCH-002] terrain. Narrowing recorded
     in the outcome record per the Pass-A wording carve-out.)
  4. Allowlist (sibling `.test-target-layer-allowlist`, lines
     `<repo-name> <test-target-name>`) for sanctioned exceptions
     ([ARCH-LAYER-012] option 2). Harness fixtures use the
     `swift-institute-test/` repo-name prefix in their entries.

Output: TSV findings `repo<TAB>ARCH-LAYER-012<TAB>message` (validate_lib.emit).

Usage:
  validate-test-target-layers.py <repo-name> <repo-root>

Exit codes: 0 scan complete (findings, if any, on stdout); 2 environment /
invocation defect (missing root, dump-package failure).

Provenance: HANDOFF-meta-ecosystem-followups §1(e) staged spec (seat-approved
2026-07-05); promoted via /promote-rule per HANDOFF-mechanization-arc W1.
Outcome record: swift-institute/Audits/PROMOTE-ARCH-LAYER-012-2026-07-06.md.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from validate_lib import emit

RULE = "ARCH-LAYER-012"

L2_PREFIXES = ("swift-rfc-", "swift-iso-", "swift-ietf-", "swift-ieee-",
               "swift-w3c-", "swift-whatwg-", "swift-ecma-", "swift-incits-",
               "swift-iec-")

# The layer taxonomy applies to institute packages only; deps hosted outside
# these orgs (swift-syntax, swift-collections, …) are layer-exempt.
# Layer derivation is ORG-FIRST: the publishing org IS the layer position
# (swift-standard-library-extensions lives in the swift-primitives org and is
# L1 despite its non-`-primitives` name — name-only mapping misclassified it
# as L3 in the first validation sweep). Name-based mapping is the fallback
# for hosts/deps whose org is underivable (e.g. harness fixtures).
ORG_LAYER = {
    "swift-primitives": 1,
    "swift-standards": 2,
    # Standards per-authority sub-orgs + vendor orgs are L2:
    "swift-ietf": 2, "swift-iso": 2, "swift-w3c": 2, "swift-whatwg": 2,
    "swift-ecma": 2, "swift-incits": 2, "swift-ieee": 2, "swift-iec": 2,
    "swift-arm-ltd": 2, "swift-intel": 2, "swift-riscv": 2,
    "swift-linux-foundation": 2, "swift-microsoft": 2,
    "swift-foundations": 3,
}
INSTITUTE_ORGS = frozenset(ORG_LAYER) | {"swift-institute"}


def layer(name: str, org: str | None = None) -> int | None:
    if org and org in ORG_LAYER:
        return ORG_LAYER[org]
    n = name.lower()
    if n.endswith("-primitives"):
        return 1
    if n.startswith(L2_PREFIXES) or n.endswith("-standard"):
        return 2
    if n.startswith("swift-"):
        return 3
    return None


def load_allowlist(script_dir: Path) -> set[tuple[str, str]]:
    path = script_dir / ".test-target-layer-allowlist"
    entries: set[tuple[str, str]] = set()
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                parts = line.split(None, 1)
                if len(parts) == 2:
                    entries.add((parts[0], parts[1]))
    return entries


def dep_org(entry: dict) -> str | None:
    """Best-effort owning org of a dependency: remote URL's second-to-last
    path component, or the parent dir name of a local/mirror path."""
    location = entry.get("location") or {}
    for remote in location.get("remote") or []:
        url = remote.get("urlString") if isinstance(remote, dict) else str(remote)
        if url:
            parts = url.rstrip("/").split("/")
            if len(parts) >= 2:
                return parts[-2]
    for local in location.get("local") or []:
        path = str(local)
        parts = path.rstrip("/").split("/")
        if len(parts) >= 2:
            return parts[-2]
    path = entry.get("path")
    if path:
        parts = str(path).rstrip("/").split("/")
        if len(parts) >= 2:
            return parts[-2]
    return None


def institute_dep_orgs(manifest: dict, host_root: Path) -> dict[str, str | None]:
    """{lower-cased identity → org} for declared deps whose owning org is an
    institute org. Relative fileSystem paths resolve against the host root; a
    dep whose org cannot be determined is kept with org None (name-based
    layer fallback applies — the conservative signal for bare path deps)."""
    out: dict[str, str | None] = {}
    for dep in manifest.get("dependencies", []):
        for kind, kind_entries in dep.items():
            for entry in kind_entries:
                identity = entry.get("identity")
                if not identity:
                    continue
                org = dep_org(entry)
                if org is None and kind == "fileSystem":
                    resolved = (host_root / str(entry.get("path", ""))).resolve()
                    if len(resolved.parts) >= 2:
                        org = resolved.parts[-2]
                if org is None or org in INSTITUTE_ORGS:
                    out[identity.lower()] = org
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root>", file=sys.stderr)
        return 2
    repo, root = argv[1], Path(argv[2])
    if not (root / "Package.swift").is_file():
        print(f"# error: no Package.swift under {root}", file=sys.stderr)
        return 2

    host_name = repo.rsplit("/", 1)[-1]
    host_org = repo.rsplit("/", 1)[0] if "/" in repo else None
    host_layer = layer(host_name, host_org)
    if host_layer is None:
        return 0  # non-layered repo (tooling, docs) — rule does not apply

    try:
        proc = subprocess.run(
            ["swift", "package", "dump-package", "--package-path", str(root)],
            capture_output=True, text=True, timeout=180,
        )
    except (subprocess.SubprocessError, OSError) as e:
        print(f"# error: dump-package failed: {e}", file=sys.stderr)
        return 2
    if proc.returncode != 0:
        print(f"# error: dump-package exit {proc.returncode}: {proc.stderr.strip()[:300]}",
              file=sys.stderr)
        return 2
    manifest = json.loads(proc.stdout)

    declared = institute_dep_orgs(manifest, root)
    allowlist = load_allowlist(Path(__file__).resolve().parent)

    for target in manifest.get("targets", []):
        if target.get("type") != "test":
            continue
        target_name = target.get("name", "?")
        if (repo, target_name) in allowlist:
            continue
        for dep in target.get("dependencies", []):
            product = dep.get("product")
            if not product or len(product) < 2 or not product[1]:
                continue  # byName / target / package-unspecified — same-package
            pkg = str(product[1])
            if pkg.lower() not in declared:
                # Not a declared external dep of this manifest — out of scope
                # here ([PKG-DEP-008]'s validator owns identity mismatches).
                continue
            dep_layer = layer(pkg, declared[pkg.lower()])
            if dep_layer is None:
                continue
            if dep_layer > host_layer:
                emit(repo, RULE,
                     f"test target '{target_name}' depends on "
                     f"'{product[0]}' from L{dep_layer} package '{pkg}' — "
                     f"above the host's L{host_layer}; tests share Package.swift, "
                     f"so this is a package-level layer violation "
                     f"(restructure per [ARCH-LAYER-012], or allowlist the "
                     f"sanctioned exception)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
