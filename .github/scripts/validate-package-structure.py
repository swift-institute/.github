#!/usr/bin/env python3
"""
validate-package-structure.py — verify a SwiftPM package follows
`modularization` skill structural invariants.

Reads `swift package describe --type json` output (stdin or file argument)
and emits TSV rows for every violation.

Output format (TSV, one row per finding):
    <repo>\t<rule-id>\t<message>

Rules checked:
  [MOD-017] Multi-product packages MUST have a singular `{Domain} Primitive`
            root target (merged namespace + foundational types). A legacy
            `{Domain} Primitives Core` / `{Domain} Namespace` target is
            accepted as migration-pending (valid until next publication).
  [MOD-005] Umbrella `{Domain} Primitives` re-exports via `exports.swift` only.
            Exception: in a type/ops-split package the base plural doubles as
            the umbrella AND carries the base conformances, so the sole-source
            check is skipped for it (its `exports.swift` is still @_exported-only).
  [MOD-007] Intra-package dep DAG depth ≤ 3 from the root.
  [MOD-011] Multi-product packages MUST publish a Test Support library product.
  [MOD-012] Multi-product target names match the role-shape pattern, including
            the singular `{Domain} Primitive` root and the `{Domain} {Variant}
            Primitive` type/ops-split type modules.

Convention reference: Skills/modularization/SKILL.md. [MOD-001] (the legacy
`{Domain} Primitives Core` target) was REMOVED 2026-05-24 — its namespace +
foundational role merged into the singular `{Domain} Primitive` per
[MOD-017]/[MOD-031]; legacy Core/Namespace targets are valid until each package's
next publication-readiness, so they are accepted here rather than flagged.

Provenance: Wave 2b reference reusable (HANDOFF-skill-to-ci-cd-extraction-inventory.md
Batch 5); merged-root + type/ops-split update 2026-05-24.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter

# Target-name role shape. `Primitives?` (optional trailing s) accepts both the
# singular merged root `{Domain} Primitive` / type/ops-split type modules
# `{Domain} {Variant} Primitive` and the plural umbrella/variant forms; the
# legacy `Core`/`Namespace` suffixes remain accepted for not-yet-migrated packages.
ROLE_RE = re.compile(
    r"^(.+?)\s+(Primitives?|Foundation|Standard)"
    r"(?:\s+(Inline|Aligned|Bounded|Static|Dynamic|Small|Linear|Ring|Slab|Arena|Heap))?"
    r"(?:\s+(Core|Test Support|Namespace))?"
    r"(?:\s+Standard Library Integration)?"
    r"$"
)

# Domain-inference suffix. `Primitives?` matches both the singular root and the
# plural umbrella/variant products, so the bare `{Domain}` is contributed by both
# the root and the umbrella.
SUFFIX_RE = re.compile(r"^(.+?)\s+(Primitives?|Standard|Foundation)(?:\s+|$)")


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
    counts = Counter(candidates)
    top = max(counts.values())
    tied = [c for c in counts if counts[c] == top]
    # The umbrella `{Domain} Primitives` and the singular root `{Domain} Primitive`
    # both yield the bare `{Domain}`, while every variant token strictly lengthens
    # it — so the true domain is the shortest among the most-frequent candidates.
    return min(tied, key=lambda c: (len(c), c))


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

    # [MOD-017] Root target — the singular `{Domain} Primitive` (merged namespace +
    # foundational types). A legacy `{Domain} Primitives Core` (or layer Core) is
    # accepted as migration-pending: [MOD-001] is REMOVED but legacy packages stay
    # valid until next publication-readiness.
    root_alts = [
        f"{domain} Primitive",            # merged-root convention (current L1)
        f"{domain} Primitives Core",      # legacy Core
        f"{domain} Foundation Core",      # legacy Core (L3)
        f"{domain} Standard Core",        # legacy Core (L2)
        f"{domain} Core",                 # legacy Core (L2/L3 short form)
    ]
    if not any(n in target_names for n in root_alts):
        emit(repo, "MOD-017",
             f"Multi-product package missing root target. Expected the singular "
             f"{domain + ' Primitive'!r} (merged-root convention) or a legacy Core "
             f"target ({root_alts[1:]!r}).")
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

    # Type/ops-split detection ([MOD-036]/[MOD-004]): a package carrying singular
    # `{Domain} {Variant} Primitive` *type* modules (in addition to the bare root).
    # In such packages the base plural `{Domain} Primitives` doubles as the
    # [MOD-005] umbrella AND carries the base conformances, so it is NOT a
    # sole-`exports.swift` target — the sole-source check below is skipped for it.
    variant_type_re = re.compile(rf"^{re.escape(domain)}\s+.+\s+Primitive$")
    is_type_ops_split = any(variant_type_re.match(tn) for tn in target_names)

    umbrella_target_name = f"{domain} Primitives"
    umbrella = target_by_name.get(umbrella_target_name)
    if umbrella:
        src = umbrella.get("sources") or []
        if not is_type_ops_split and (len(src) != 1 or src[0] != "exports.swift"):
            emit(repo, "MOD-005",
                 f"Umbrella target {umbrella_target_name!r} has non-exports source files: "
                 f"{src!r}. Umbrella content MUST be only `exports.swift` with @_exported "
                 f"public import lines.")
            findings += 1
        # The `exports.swift` content check holds for the type/ops-split base plural
        # too — its `exports.swift` is @_exported-only even though sibling files carry
        # the base conformances.
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

    # [MOD-017] Namespace ownership — if the sources declare `public enum {Domain}`,
    # a namespace-owning target must exist: the singular `{Domain} Primitive`
    # (merged) or a legacy `{Domain} Namespace` / Core target (migration-pending).
    ns_owner_alts = root_alts + [f"{domain} Namespace"]
    if os.path.isdir(sources_dir):
        try:
            out = subprocess.run(
                ["grep", "-rEln", f"^public enum {re.escape(domain)}\\b", sources_dir],
                capture_output=True, text=True, timeout=10
            )
            if out.stdout.strip() and not any(n in target_names for n in ns_owner_alts):
                emit(repo, "MOD-017",
                     f"Top-level `public enum {domain}` found but no namespace-owning "
                     f"target declared (expected {domain + ' Primitive'!r}, or a legacy "
                     f"{domain + ' Namespace'!r} / Core target).")
                findings += 1
        except Exception:
            pass

    skip_suffixes = (" Core", " Test Support", " Namespace")
    for t in targets:
        tn = t.get("name", "")
        if not tn or tn == umbrella_target_name:
            continue
        # Test targets legitimately depend on the umbrella + Test Support, so they
        # are not subject to the module-DAG depth rule (mirrors the [MOD-012] loop's
        # " Tests" skip). Without this, every package's test target false-flags.
        if t.get("type") == "test" or tn.endswith(" Tests"):
            continue
        if any(tn.endswith(suf) for suf in skip_suffixes):
            continue
        d = depth_from(tn, target_by_name)
        if d > 3:
            emit(repo, "MOD-007",
                 f"Target {tn!r} has DAG depth {d} from the root (>3). "
                 f"Flatten the chain.")
            findings += 1

    for tn in sorted(target_names):
        if tn.endswith(" Tests") or tn == "Tests":
            continue
        if not ROLE_RE.match(tn):
            emit(repo, "MOD-012",
                 f"Target name {tn!r} does not match the role-shape scheme "
                 f"(singular {{Domain}} Primitive root, {{Domain}} {{Variant}} "
                 f"Primitives variant, {{Domain}} Primitives umbrella, plus the "
                 f"Test Support / Standard Library Integration / legacy Core|Namespace "
                 f"suffixes).")
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
