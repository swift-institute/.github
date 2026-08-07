#!/usr/bin/env python3
# TRANSFERRED: this predicate's Swift realisation is owned by the Foundation
# Programme's TX-APP1W (CW transfer ruling: swift-institute/.github#358
# comment 5215227317; migration preimage: comment 5215128447). This file is
# retained verbatim until its Swift owner's activation receipt; its deletion
# rides that gate. Do not port, modify, or delete it under Goal #358.

"""Audit dependency integrity for existing ``* Test Support`` targets.

The audit does not require every package with tests to publish Test Support.
Product publication is an architecture decision. When a package does publish a
Test Support target, its dependencies must stay within the package's supported
products and deliberate upstream Test Support products.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ENTRY_ROOT = Path(
    os.environ.get("SWIFT_INSTITUTE_ENTRY_ROOT", Path.home() / "Developer" / "coenttb")
)
INSTITUTE_ROOT = ENTRY_ROOT / "swift-institute"
STANDARDS_ROOT = INSTITUTE_ROOT / "swift-standards"
ORG_DIRS = {
    "primitives": INSTITUTE_ROOT / "swift-primitives",
    "standards": STANDARDS_ROOT,
    "foundations": INSTITUTE_ROOT / "swift-foundations",
    "iso": STANDARDS_ROOT / "swift-iso",
}
TS_SUFFIX = " Test Support"


def is_test_support(name: str) -> bool:
    return name.endswith(TS_SUFFIX)


def packages(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(
        child
        for child in root.iterdir()
        if child.is_dir() and (child / "Package.swift").is_file()
    )


def dump_package(root: Path) -> dict | None:
    try:
        result = subprocess.run(
            ["swift", "package", "dump-package"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def product_targets(package: dict) -> set[str]:
    return {
        target
        for product in package.get("products", [])
        for target in product.get("targets", [])
    }


def dependency_name(entry: dict) -> tuple[str, str]:
    for kind in ("byName", "target", "product"):
        if kind not in entry:
            continue
        raw = entry[kind]
        if isinstance(raw, list):
            return kind, raw[0] if raw else ""
        return kind, raw
    return "unknown", json.dumps(entry, sort_keys=True)


def audit_package(root: Path, package: dict) -> dict:
    owned_products = product_targets(package)
    findings: list[dict] = []
    target_names: list[str] = []

    for target in package.get("targets", []):
        target_name = target.get("name", "")
        if not is_test_support(target_name):
            continue
        target_names.append(target_name)
        violations = []
        for dependency in target.get("dependencies", []):
            kind, name = dependency_name(dependency)
            if is_test_support(name) or name in owned_products:
                continue
            violations.append({"kind": kind, "name": name})

        findings.append(
            {
                "type": "VIOLATION" if violations else "OK",
                "package": package.get("name", root.name),
                "target": target_name,
                "violations": violations,
            }
        )

    return {
        "package": package.get("name", root.name),
        "dir": str(root),
        "test_support_targets": target_names,
        "findings": findings,
    }


def audit_org(name: str, root: Path) -> dict:
    audited = []
    failures = []
    for package_root in packages(root):
        package = dump_package(package_root)
        if package is None:
            failures.append(package_root.name)
        else:
            audited.append(audit_package(package_root, package))
    return {
        "org": name,
        "dir": str(root),
        "packages": audited,
        "parse_failures": failures,
    }


def aggregate(orgs: list[dict]) -> dict:
    findings = [
        finding
        for org in orgs
        for package in org["packages"]
        for finding in package["findings"]
    ]
    return {
        "totals": {
            "audited_targets": len(findings),
            "ok_findings": sum(f["type"] == "OK" for f in findings),
            "violation_findings": sum(f["type"] == "VIOLATION" for f in findings),
            "parse_failures": sum(len(org["parse_failures"]) for org in orgs),
        }
    }


def print_report(orgs: list[dict], summary: dict) -> None:
    print("Test Support dependency audit")
    for org in orgs:
        print(f"\n## {org['org']} ({org['dir']})")
        if org["parse_failures"]:
            print(f"Parse failures: {', '.join(org['parse_failures'])}")
        for package in org["packages"]:
            for finding in package["findings"]:
                if finding["type"] == "OK":
                    continue
                print(f"{package['package']}: {finding['target']}")
                for violation in finding["violations"]:
                    print(
                        "  non-spine dependency: "
                        f"{violation['kind']} {violation['name']}"
                    )

    totals = summary["totals"]
    print("\n## Aggregate")
    print(f"Audited targets: {totals['audited_targets']}")
    print(f"OK: {totals['ok_findings']}")
    print(f"Violations: {totals['violation_findings']}")
    print(f"Parse failures: {totals['parse_failures']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--org", choices=sorted(ORG_DIRS))
    mode.add_argument("--package-dir", type=Path)
    parser.add_argument("--json", type=Path)
    arguments = parser.parse_args()

    if arguments.package_dir:
        root = arguments.package_dir.resolve()
        if not (root / "Package.swift").is_file():
            print(f"error: {root}/Package.swift not found", file=sys.stderr)
            return 2
        package = dump_package(root)
        if package is None:
            print(f"error: swift package dump-package failed in {root}", file=sys.stderr)
            return 2
        orgs = [
            {
                "org": "<single>",
                "dir": str(root.parent),
                "packages": [audit_package(root, package)],
                "parse_failures": [],
            }
        ]
    else:
        names = [arguments.org] if arguments.org else sorted(ORG_DIRS)
        missing = [name for name in names if not ORG_DIRS[name].is_dir()]
        if missing:
            for name in missing:
                print(f"error: {ORG_DIRS[name]} not found", file=sys.stderr)
            return 2
        orgs = [audit_org(name, ORG_DIRS[name]) for name in names]

    summary = aggregate(orgs)
    print_report(orgs, summary)
    if arguments.json:
        arguments.json.write_text(
            json.dumps({"orgs": orgs, "aggregate": summary}, indent=2),
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
