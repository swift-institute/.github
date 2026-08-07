#!/usr/bin/env python3
# TRANSFERRED: this predicate's Swift realisation is owned by the Foundation
# Programme's TX-APP1W (CW transfer ruling: swift-institute/.github#358
# comment 5215227317; migration preimage: comment 5215128447). This file is
# retained verbatim until its Swift owner's activation receipt; its deletion
# rides that gate. Do not port, modify, or delete it under Goal #358.

"""Validate shape-neutral SwiftPM package structure.

The validator consumes ``swift package describe --type json`` output and emits
TSV findings:

    <repo>\t<diagnostic-id>\t<message>

It intentionally does not decide whether a package needs a root, umbrella,
variant, or Test Support target. Those are architecture decisions. It verifies
only graph integrity and the mechanically identifiable exports-only aggregate
shape.
"""
from __future__ import annotations

import glob as globmod
import json
import os
import sys


def emit(repo: str, diagnostic: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{diagnostic}\t{safe}")


def swift_sources(target: dict) -> list[str]:
    sources = target.get("sources")
    if sources is not None:
        return sorted(
            source for source in sources
            if source.endswith(".swift")
            and not any(part.endswith(".docc") for part in source.split(os.sep))
        )

    path = target.get("path") or os.path.join("Sources", target.get("name", ""))
    return sorted(
        os.path.relpath(source, path)
        for source in globmod.glob(os.path.join(path, "**", "*.swift"), recursive=True)
        if not any(
            part.endswith(".docc")
            for part in os.path.relpath(source, path).split(os.sep)
        )
    )


def target_cycles(targets: dict[str, dict]) -> list[list[str]]:
    cycles: list[list[str]] = []
    complete: set[str] = set()
    visiting: list[str] = []

    def visit(name: str) -> None:
        if name in complete:
            return
        if name in visiting:
            start = visiting.index(name)
            cycles.append(visiting[start:] + [name])
            return

        visiting.append(name)
        for dependency in targets[name].get("target_dependencies") or []:
            if dependency in targets:
                visit(dependency)
        visiting.pop()
        complete.add(name)

    for name in sorted(targets):
        visit(name)
    return cycles


def validate(repo: str, package: dict) -> int:
    raw_targets = package.get("targets") or []
    targets = {
        target.get("name", ""): target
        for target in raw_targets
        if target.get("name")
    }
    findings = 0

    if len(targets) != len(raw_targets):
        emit(
            repo,
            "PACKAGE-TARGET-IDENTITY",
            "Every described target must have one unique non-empty name.",
        )
        findings += 1

    for target_name, target in sorted(targets.items()):
        for dependency in target.get("target_dependencies") or []:
            if dependency not in targets:
                emit(
                    repo,
                    "PACKAGE-TARGET-EDGE",
                    f"Target {target_name!r} references missing target {dependency!r}.",
                )
                findings += 1

    for cycle in target_cycles(targets):
        emit(
            repo,
            "PACKAGE-TARGET-CYCLE",
            f"Target dependency cycle: {' -> '.join(cycle)}.",
        )
        findings += 1

    for product in package.get("products") or []:
        product_name = product.get("name", "")
        for target_name in product.get("targets") or []:
            if target_name not in targets:
                emit(
                    repo,
                    "PACKAGE-PRODUCT-TARGET",
                    f"Product {product_name!r} references missing target {target_name!r}.",
                )
                findings += 1

    for target_name, target in sorted(targets.items()):
        sources = swift_sources(target)
        if sources != ["exports.swift"]:
            continue

        target_path = target.get("path") or os.path.join("Sources", target_name)
        exports_path = os.path.join(target_path, "exports.swift")
        if not os.path.isfile(exports_path):
            continue

        with open(exports_path, encoding="utf-8") as source:
            lines = [
                line.strip()
                for line in source
                if line.strip() and not line.lstrip().startswith("//")
            ]
        invalid = [
            line for line in lines
            if not line.startswith("@_exported public import ")
        ]
        if invalid:
            emit(
                repo,
                "PACKAGE-AGGREGATE-EXPORT",
                f"Exports-only target {target_name!r} contains non-export content: "
                f"{invalid[0]!r}.",
            )
            findings += 1

    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) > 3:
        print(f"usage: {argv[0]} <repo-name> [package.json]", file=sys.stderr)
        return 2

    if len(argv) == 3:
        with open(argv[2], encoding="utf-8") as source:
            package = json.load(source)
    else:
        package = json.load(sys.stdin)

    findings = validate(argv[1], package)
    return 0 if findings == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
