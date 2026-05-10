#!/usr/bin/env python3
"""
validate-package-structure.py — verify a SwiftPM package follows
`modularization` skill structural invariants.

Wave 2b reference reusable helper. Reads `swift package describe --type json`
output (stdin or file argument) and emits TSV rows for every violation.

Output format (TSV, one row per finding):
    <repo>\t<rule-id>\t<message>

Rules checked (v1):
  [MOD-001] Multi-product packages MUST have a Core target.
  [MOD-005] Umbrella target's sole content is `@_exported public import` lines.
  [MOD-007] Intra-package dep DAG depth ≤ 3 from Core.
  [MOD-011] Multi-product packages MUST publish Test Support library product.
  [MOD-012] Multi-product target names match the role-shape pattern.
  [MOD-017] Top-level namespace declarations MUST have a Namespace target.

Provenance: Wave 2b execution (HANDOFF-skill-to-ci-cd-extraction-inventory.md
Batch 5 reference reusable). Skills/modularization/SKILL.md.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter

ROLE_RE = re.compile(
    r"^(.+?)\s+(Primitives|Foundation|Standard)"
    r"(?:\s+(Inline|Aligned|Bounded|Static|Dynamic|Small|Linear|Ring|Slab|Arena|Heap))?"
    r"(?:\s+(Core|Test Support|Namespace))?"
    r"(?:\s+Standard Library Integration)?"
    r"$"
)

SUFFIX_RE = re.compile(r"^(.+?)\s+(Primitives|Standard|Foundation)(?:\s+|$)")


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def infer_domain(non_meta_products: list[dict]) -> str | None:
    candidates = []
    for p in non_meta_products:
        m = SUFFIX_RE.match(p.get("name", ""))
        if m:
            candidates.append(m.group(1))
    if not candidates:
        return None
    return Counter(candidates).most_common(1)[0][0]


def depth_from(node: str, target_by_name: dict, visited: set[str] | None = None) -> int:
    if visited is None:
        visited = set()
    if node in visited:
        return 0
    visited.add(node)
    target = target_by_name.get(node)
    if not target:
        return 0
    deps = list(target.get("target_dependencies") or [])
    if not deps:
        return 1
    return 1 + max(depth_from(d, target_by_name, visited.copy()) for d in deps)


def validate(repo: str, pkg: dict, sources_dir: str = "Sources") -> int:
    products = pkg.get("products") or []
    targets = pkg.get("targets") or []
    target_names = {t.get("name", "") for t in targets}
    product_names = {p.get("name", "") for p in products}
    target_by_name = {t.get("name", ""): t for t in targets}

    non_meta_products = [
        p for p in products
        if not p.get("name", "").endswith(" Test Support")
        and not p.get("name", "").endswith(" Namespace")
    ]
    multi_product = len(non_meta_products) >= 2
    if not multi_product:
        return 0

    domain = infer_domain(non_meta_products)
    if not domain:
        emit(repo, "MOD-012-domain-undetectable",
             "Could not infer {Domain} from product names; manual review.")
        return 1

    findings = 0

    core_alts = [
        f"{domain} Primitives Core",
        f"{domain} Foundation Core",
        f"{domain} Standard Core",
        f"{domain} Core",
    ]
    if not any(n in target_names for n in core_alts):
        emit(repo, "MOD-001",
             f"Multi-product package missing Core target. Expected one of: "
             f"{core_alts!r}.")
        findings += 1

    ts_alts = [
        f"{domain} Primitives Test Support",
        f"{domain} Foundation Test Support",
        f"{domain} Standard Test Support",
        f"{domain} Test Support",
    ]
    if not any(n in product_names for n in ts_alts):
        emit(repo, "MOD-011",
             f"Multi-product package missing Test Support library product. "
             f"Expected one of: {ts_alts!r}.")
        findings += 1

    umbrella_target_name = f"{domain} Primitives"
    umbrella = target_by_name.get(umbrella_target_name)
    if umbrella:
        src = umbrella.get("sources") or []
        if len(src) != 1 or src[0] != "exports.swift":
            emit(repo, "MOD-005",
                 f"Umbrella target {umbrella_target_name!r} has non-exports source files: "
                 f"{src!r}. Umbrella content MUST be only `exports.swift` with @_exported "
                 f"public import lines.")
            findings += 1
        else:
            ts_path = umbrella.get("path") or f"Sources/{umbrella_target_name}"
            exports_swift = os.path.join(ts_path, "exports.swift")
            if os.path.isfile(exports_swift):
                with open(exports_swift) as f:
                    lines = [ln.rstrip() for ln in f
                             if ln.strip() and not ln.lstrip().startswith("//")]
                non_exported = [ln for ln in lines
                                if not ln.startswith("@_exported public import")]
                if non_exported:
                    emit(repo, "MOD-005",
                         f"Umbrella exports.swift contains non-`@_exported public import` "
                         f"content: first offender = {non_exported[0]!r}.")
                    findings += 1

    ns_target_name = f"{domain} Namespace"
    if os.path.isdir(sources_dir):
        try:
            out = subprocess.run(
                ["grep", "-rEln", f"^public enum {re.escape(domain)}\\b", sources_dir],
                capture_output=True, text=True, timeout=10
            )
            if out.stdout.strip() and ns_target_name not in target_names:
                emit(repo, "MOD-017",
                     f"Top-level `public enum {domain}` found but no "
                     f"{ns_target_name!r} target declared.")
                findings += 1
        except Exception:
            pass

    skip_suffixes = (" Core", " Test Support", " Namespace")
    for t in targets:
        tn = t.get("name", "")
        if not tn or tn == umbrella_target_name:
            continue
        if any(tn.endswith(suf) for suf in skip_suffixes):
            continue
        d = depth_from(tn, target_by_name)
        if d > 3:
            emit(repo, "MOD-007",
                 f"Target {tn!r} has DAG depth {d} from Core (>3). "
                 f"Flatten the chain.")
            findings += 1

    for tn in sorted(target_names):
        if tn.endswith(" Tests") or tn == "Tests":
            continue
        if not ROLE_RE.match(tn):
            emit(repo, "MOD-012",
                 f"Target name {tn!r} does not match the {{Domain}} "
                 f"{{Primitives|Foundation|Standard}}({{Variant}})?"
                 f"({{Core|Test Support|Namespace}})? scheme.")
            findings += 1

    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) > 3:
        print(f"usage: {argv[0]} <repo-name> [pkg.json]", file=sys.stderr)
        return 2
    repo = argv[1]
    if len(argv) == 3:
        with open(argv[2]) as f:
            pkg = json.load(f)
    else:
        pkg = json.load(sys.stdin)
    findings = validate(repo, pkg)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
