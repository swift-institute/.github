#!/usr/bin/env python3
"""
Audit script for the Test Support spine rule ([MOD-024]).

Walks each org-dir's Package.swift via `swift package dump-package`, audits
every `* Test Support` target against the rule "TS target deps subset of
{TS modules, own product}", and emits per-target findings plus a
strict-vs-pragmatic shell-candidate analysis.

Outputs (stdout):
  - Per-package findings (OK / VIOLATION / MISSING)
  - Per-org summary
  - Aggregate violations table (which non-TS packages would need shells under
    pragmatic disposition)
  - Strict-vs-pragmatic delta

Optional JSON output via --json <path>.

Usage:
  audit-test-support-spine.py                              # all four org-dirs (principal mode)
  audit-test-support-spine.py --org primitives             # single org (principal mode)
  audit-test-support-spine.py --package-dir <path>         # single package (CI mode)
  audit-test-support-spine.py --json /tmp/spine-audit.json
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ORG_DIRS = {
    "primitives": Path("/Users/coen/Developer/swift-primitives"),
    "standards": Path("/Users/coen/Developer/swift-standards"),
    "foundations": Path("/Users/coen/Developer/swift-foundations"),
    "iso": Path("/Users/coen/Developer/swift-iso"),
}

TS_SUFFIX = " Test Support"


def is_ts_name(name: str) -> bool:
    return name.endswith(TS_SUFFIX)


def list_packages(org_dir: Path) -> list[Path]:
    """Return sub-directories that contain a top-level Package.swift."""
    if not org_dir.is_dir():
        return []
    return sorted(
        sub for sub in org_dir.iterdir()
        if sub.is_dir() and (sub / "Package.swift").is_file()
    )


def dump_package(pkg_dir: Path) -> dict | None:
    """Parse Package.swift via `swift package dump-package`. Returns None on failure."""
    try:
        result = subprocess.run(
            ["swift", "package", "dump-package"],
            cwd=str(pkg_dir),
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def own_product_target_names(pkg: dict) -> set[str]:
    """Targets named in any library product — these are the package's 'own products' for dep-checking."""
    names: set[str] = set()
    for product in pkg.get("products", []):
        for t in product.get("targets", []):
            names.add(t)
    return names


def classify_dep(dep: dict, own_products: set[str]) -> tuple[str, str, str | None]:
    """
    Classify a dependency entry from dump-package output.
    Returns (category, name, package) where:
      category: "ts" | "own-product" | "non-ts-target" | "non-ts-product" | "unknown"
      name: target/product name
      package: package name for "*-product" categories, else None
    """
    if "byName" in dep:
        name = dep["byName"][0]
        if is_ts_name(name):
            return ("ts", name, None)
        if name in own_products:
            return ("own-product", name, None)
        return ("non-ts-target", name, None)
    if "target" in dep:
        raw = dep["target"]
        name = raw[0] if isinstance(raw, list) else raw
        if is_ts_name(name):
            return ("ts", name, None)
        if name in own_products:
            return ("own-product", name, None)
        return ("non-ts-target", name, None)
    if "product" in dep:
        raw = dep["product"]
        name = raw[0]
        package = raw[1] if len(raw) > 1 else None
        if is_ts_name(name):
            return ("ts", name, package)
        return ("non-ts-product", name, package)
    return ("unknown", json.dumps(dep), None)


def audit_package(pkg_dir: Path, pkg: dict) -> dict:
    """Audit a single package; return structured findings."""
    pkg_name = pkg.get("name", pkg_dir.name)
    targets = pkg.get("targets", [])
    own_products = own_product_target_names(pkg)
    ts_targets = [t for t in targets if is_ts_name(t["name"])]
    test_targets = [t for t in targets if t.get("type") == "test"]

    findings: list[dict] = []

    if test_targets and not ts_targets:
        findings.append({
            "type": "MISSING",
            "package": pkg_name,
            "test_target_count": len(test_targets),
        })

    for ts in ts_targets:
        ts_name = ts["name"]
        deps = ts.get("dependencies", [])
        violations: list[dict] = []
        for dep in deps:
            category, name, package = classify_dep(dep, own_products)
            if category in ("ts", "own-product"):
                continue
            violations.append({
                "category": category,
                "name": name,
                "package": package,
            })
        if violations:
            findings.append({
                "type": "VIOLATION",
                "package": pkg_name,
                "ts_target": ts_name,
                "violations": violations,
            })
        else:
            findings.append({
                "type": "OK",
                "package": pkg_name,
                "ts_target": ts_name,
            })

    return {
        "package": pkg_name,
        "dir": str(pkg_dir),
        "ts_targets": [t["name"] for t in ts_targets],
        "test_targets": [t["name"] for t in test_targets],
        "findings": findings,
    }


def audit_org(org_name: str, org_dir: Path) -> dict:
    pkgs = list_packages(org_dir)
    audited: list[dict] = []
    parse_failures: list[str] = []
    for pkg_dir in pkgs:
        dump = dump_package(pkg_dir)
        if dump is None:
            parse_failures.append(pkg_dir.name)
            continue
        audited.append(audit_package(pkg_dir, dump))
    return {
        "org": org_name,
        "dir": str(org_dir),
        "packages": audited,
        "parse_failures": parse_failures,
    }


def aggregate(orgs: list[dict]) -> dict:
    """Aggregate stats + strict/pragmatic shell-candidate sets."""
    all_packages_with_ts: set[str] = set()
    all_packages_without_ts: set[str] = set()
    all_packages_with_tests: set[str] = set()

    pragmatic_candidates: set[str] = set()  # cross-package non-TS products
    pragmatic_candidate_pkgs: set[str] = set()  # the OWNING packages of those products

    violation_count = 0
    ok_count = 0
    missing_count = 0

    for org in orgs:
        for p in org["packages"]:
            name = p["package"]
            if p["ts_targets"]:
                all_packages_with_ts.add(name)
            else:
                all_packages_without_ts.add(name)
            if p["test_targets"]:
                all_packages_with_tests.add(name)
            for f in p["findings"]:
                if f["type"] == "OK":
                    ok_count += 1
                elif f["type"] == "MISSING":
                    missing_count += 1
                elif f["type"] == "VIOLATION":
                    violation_count += 1
                    for v in f["violations"]:
                        if v["category"] == "non-ts-product" and v["package"]:
                            pragmatic_candidates.add(v["name"])
                            pragmatic_candidate_pkgs.add(v["package"])

    # "Strict" = every package with tests but no TS gets a shell.
    strict_candidate_pkgs = {
        p["package"] for org in orgs for p in org["packages"]
        if p["test_targets"] and not p["ts_targets"]
    }

    return {
        "totals": {
            "packages_with_ts": len(all_packages_with_ts),
            "packages_without_ts": len(all_packages_without_ts),
            "packages_with_tests": len(all_packages_with_tests),
            "ok_findings": ok_count,
            "violation_findings": violation_count,
            "missing_findings": missing_count,
        },
        "strict_candidate_pkgs": sorted(strict_candidate_pkgs),
        "pragmatic_candidate_products": sorted(pragmatic_candidates),
        "pragmatic_candidate_pkgs": sorted(pragmatic_candidate_pkgs),
    }


def print_report(orgs: list[dict], agg: dict) -> None:
    print("=" * 78)
    print("Test Support Spine — Pre-Flight Audit Report")
    print("=" * 78)

    for org in orgs:
        print(f"\n## {org['org']}  ({org['dir']})")
        if org["parse_failures"]:
            print(f"  Parse failures: {len(org['parse_failures'])} — {org['parse_failures']}")
        ok = sum(1 for p in org["packages"] for f in p["findings"] if f["type"] == "OK")
        viol = sum(1 for p in org["packages"] for f in p["findings"] if f["type"] == "VIOLATION")
        miss = sum(1 for p in org["packages"] for f in p["findings"] if f["type"] == "MISSING")
        print(f"  Packages: {len(org['packages'])}  |  OK: {ok}  Violations: {viol}  Missing: {miss}")

        for p in org["packages"]:
            findings = p["findings"]
            if not findings:
                continue
            relevant = [f for f in findings if f["type"] != "OK"]
            if not relevant:
                continue
            print(f"\n  {p['package']}")
            for f in relevant:
                if f["type"] == "MISSING":
                    print(f"    MISSING: has {f['test_target_count']} test target(s) but no TS target")
                elif f["type"] == "VIOLATION":
                    print(f"    VIOLATION: {f['ts_target']}")
                    for v in f["violations"]:
                        if v["category"] == "non-ts-product":
                            print(f"      non-TS cross-package product: {v['name']}  (from {v['package']})")
                        else:
                            print(f"      non-TS {v['category']}: {v['name']}")

    print()
    print("=" * 78)
    print("Aggregate")
    print("=" * 78)
    t = agg["totals"]
    print(f"  Packages with TS:    {t['packages_with_ts']}")
    print(f"  Packages without TS: {t['packages_without_ts']}")
    print(f"  Packages with tests: {t['packages_with_tests']}")
    print(f"  OK findings:         {t['ok_findings']}")
    print(f"  Violation findings:  {t['violation_findings']}")
    print(f"  Missing findings:    {t['missing_findings']}")
    print()
    print(f"  STRICT shell candidates ({len(agg['strict_candidate_pkgs'])}):")
    print(f"    Every package with tests but no TS target gets a shell.")
    print()
    print(f"  PRAGMATIC shell candidates ({len(agg['pragmatic_candidate_pkgs'])}):")
    print(f"    Packages whose products appear as non-TS cross-package deps in some TS target.")
    for pkg in agg["pragmatic_candidate_pkgs"]:
        print(f"    - {pkg}")
    print()
    print(f"  STRICT - PRAGMATIC delta: {len(agg['strict_candidate_pkgs']) - len(agg['pragmatic_candidate_pkgs'])} packages")
    print(f"    (under pragmatic, these have tests but are NOT reached by any TS target's deps,")
    print(f"     so they don't need a shell for SLI propagation)")


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--org", choices=sorted(ORG_DIRS.keys()),
                      help="Audit one org-dir only (principal mode)")
    mode.add_argument("--package-dir", type=Path,
                      help="Audit a single package at this path (CI mode)")
    ap.add_argument("--json", type=Path, help="Write raw findings to this JSON path")
    args = ap.parse_args()

    if args.package_dir:
        pkg_dir = args.package_dir.resolve()
        if not (pkg_dir / "Package.swift").is_file():
            print(f"error: {pkg_dir}/Package.swift not found", file=sys.stderr)
            return 2
        print(f"auditing single package at {pkg_dir} ...", file=sys.stderr)
        dump = dump_package(pkg_dir)
        if dump is None:
            print(f"error: swift package dump-package failed in {pkg_dir}", file=sys.stderr)
            return 2
        audited = audit_package(pkg_dir, dump)
        orgs = [{"org": "<single>", "dir": str(pkg_dir.parent),
                 "packages": [audited], "parse_failures": []}]
    else:
        org_names = [args.org] if args.org else sorted(ORG_DIRS.keys())
        orgs = []
        for name in org_names:
            org_dir = ORG_DIRS[name]
            if not org_dir.is_dir():
                print(f"warning: {org_dir} not found, skipping", file=sys.stderr)
                continue
            print(f"auditing {name} at {org_dir} ...", file=sys.stderr)
            orgs.append(audit_org(name, org_dir))

    agg = aggregate(orgs)
    print_report(orgs, agg)

    if args.json:
        args.json.write_text(json.dumps({"orgs": orgs, "aggregate": agg}, indent=2))
        print(f"\nJSON output written to {args.json}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
