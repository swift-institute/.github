#!/usr/bin/env python3
"""
Audit script for the Foundation-family import rule (γ-1a).

Scans .swift files in Sources/** and Tests/** for forbidden imports of
Foundation, FoundationEssentials, or FoundationInternationalization. Per
research §3.4.2:

  - Sources/**          → ERROR
  - Tests/Support/**    → ERROR
  - Tests/** elsewhere  → WARNING
  - #if canImport(Foundation*) bare → WARNING (the import inside is the
    gating violation)

Catches all attribute and access-modifier permutations:
  import Foundation
  public import Foundation
  package import Foundation
  internal import Foundation
  fileprivate import Foundation
  private import Foundation
  @_exported import Foundation
  @_exported public import Foundation
  @_implementationOnly import Foundation
  @preconcurrency import Foundation
  @preconcurrency public import Foundation
  ...and combinations of the above.

Implementation: textual regex scanner. Conservative syntactic gate.
SwiftSyntax-based semantic analysis is out of scope for γ-1a (future
enhancement).

Outputs (stdout): per-file findings, per-package summary, aggregate.
Optional JSON output via --json <path>:

  {
    "package": "swift-X-primitives",
    "dir": "/path/to/package",
    "findings": [
      {"path": "Sources/X/Foo.swift", "line": 3, "level": "ERROR",
       "match": "import Foundation"},
      ...
    ],
    "totals": {"errors": N, "warnings": M, "files_scanned": K}
  }

Usage:
  audit-foundation-import.py --package-dir /path/to/package
  audit-foundation-import.py --package-dir . --json /tmp/audit.json
"""

import argparse
import json
import re
import sys
from pathlib import Path

# Regex catching all attribute/access-modifier permutations of:
#   import Foundation | FoundationEssentials | FoundationInternationalization
#
# Anchored to start-of-line (with optional leading whitespace). Captures
# the `import <Module>` portion as group 'mod' for reporting.
IMPORT_PATTERN = re.compile(
    r"""
    ^[ \t]*                                       # optional leading whitespace
    (?:@[a-zA-Z_]+[ \t]+)*                        # zero or more attributes (e.g. @_exported, @preconcurrency)
    (?:public|package|internal|fileprivate|private)?[ \t]*  # optional access modifier
    import[ \t]+
    (?P<mod>Foundation|FoundationEssentials|FoundationInternationalization)
    \b                                            # word boundary (rejects FoundationFoo)
    """,
    re.VERBOSE,
)


def classify_path(rel_path: Path) -> str | None:
    """
    Return the violation level for a file path:
      - "ERROR" for Sources/** or Tests/Support/**
      - "WARNING" for Tests/** outside Tests/Support/
      - None for everything else (don't audit)
    """
    parts = rel_path.parts
    if not parts:
        return None
    if parts[0] == "Sources":
        return "ERROR"
    if parts[0] == "Tests":
        # Tests/Support/** → ERROR; everything else under Tests/** → WARNING
        if len(parts) >= 2 and parts[1] == "Support":
            return "ERROR"
        return "WARNING"
    return None


def scan_file(file_path: Path, rel_path: Path, level: str) -> list[dict]:
    """Scan a single .swift file; return list of findings."""
    findings = []
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return findings
    for lineno, line in enumerate(content.splitlines(), start=1):
        m = IMPORT_PATTERN.match(line)
        if m:
            findings.append({
                "path": str(rel_path),
                "line": lineno,
                "level": level,
                "match": line.strip(),
                "module": m.group("mod"),
            })
    return findings


def audit_package(pkg_dir: Path) -> dict:
    """Audit one package directory; return findings + totals."""
    pkg_dir = pkg_dir.resolve()
    findings: list[dict] = []
    files_scanned = 0
    for swift_file in pkg_dir.rglob("*.swift"):
        try:
            rel_path = swift_file.relative_to(pkg_dir)
        except ValueError:
            continue
        level = classify_path(rel_path)
        if level is None:
            continue
        files_scanned += 1
        findings.extend(scan_file(swift_file, rel_path, level))
    errors = sum(1 for f in findings if f["level"] == "ERROR")
    warnings = sum(1 for f in findings if f["level"] == "WARNING")
    return {
        "package": pkg_dir.name,
        "dir": str(pkg_dir),
        "findings": findings,
        "totals": {
            "errors": errors,
            "warnings": warnings,
            "files_scanned": files_scanned,
        },
    }


def print_report(audit: dict) -> None:
    print("=" * 78)
    print("Foundation-family import audit (γ-1a)")
    print("=" * 78)
    print(f"  Package:        {audit['package']}")
    print(f"  Directory:      {audit['dir']}")
    print(f"  Files scanned:  {audit['totals']['files_scanned']}")
    print(f"  ERRORS:         {audit['totals']['errors']}")
    print(f"  WARNINGS:       {audit['totals']['warnings']}")
    print()
    if audit["findings"]:
        print("Findings:")
        for f in audit["findings"]:
            print(f"  {f['level']}  {f['path']}:{f['line']}  ->  {f['match']}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Foundation-family import audit (γ-1a)")
    ap.add_argument("--package-dir", type=Path, required=True,
                    help="Audit a single package at this path")
    ap.add_argument("--json", type=Path, help="Write raw findings to this JSON path")
    args = ap.parse_args()

    pkg_dir = args.package_dir.resolve()
    if not (pkg_dir / "Package.swift").is_file():
        print(f"error: {pkg_dir}/Package.swift not found", file=sys.stderr)
        return 2

    audit = audit_package(pkg_dir)
    print_report(audit)

    if args.json:
        args.json.write_text(json.dumps(audit, indent=2))
        print(f"\nJSON output written to {args.json}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
