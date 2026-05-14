#!/usr/bin/env python3
"""
Audit script for the γ-2 mechanical-hygiene rule (consolidated yamllint
+ broken-symlink scan).

Per-package shape (CI mode):
    audit-mechanical-hygiene.py --package-dir /path/to/clone --json /tmp/audit.json

Output JSON:
    {
        "package": "swift-X-primitives",
        "dir": "/path/to/clone",
        "totals": {
            "yaml_issues": N,
            "broken_links": M
        }
    }

yamllint scope (per Research §3.4.5):
    .github/workflows/**/*.{yml,yaml}
    .github/dependabot.yml
    .github/metadata.yaml
    metadata.yaml

Excludes (per [CI-057] per-package autonomy):
    .swiftlint.yml, .swift-format

Broken-symlink scope: anywhere in the repo (find -L . -type l !
-exec test -e ...).

Counter-shape (yaml_issues): the count is the number of yamllint
diagnostic lines whose shape matches `^\\s+\\d+:\\d+`. Mirrors the
counting style from the prior inline shell snippet preserved by Phase C
of the 2026-05-14 CI review.

Counter-shape (broken_links): integer count of dangling symlinks
discovered by `find -L . -type l ! -exec test -e {} \\;`.

The yamllint binary + /tmp/yamllint.yml config are NOT installed by
this script — that is the responsibility of the audit-setup-script
(see audit-setup-yamllint.py, invoked once per matrix job by
cron-audit-base.yml's structured-input contract).
"""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

YAMLLINT_CONFIG = "/tmp/yamllint.yml"

YAML_TARGETS = [
    (".github/workflows", True),     # directory
    (".github/dependabot.yml", False),
    (".github/metadata.yaml", False),
    ("metadata.yaml", False),
]


def collect_yaml_paths(pkg_dir: Path) -> list[str]:
    paths: list[str] = []
    for rel, is_dir in YAML_TARGETS:
        target = pkg_dir / rel
        if is_dir and target.is_dir():
            paths.append(str(target))
        elif (not is_dir) and target.is_file():
            paths.append(str(target))
    return paths


def count_yaml_issues(paths: list[str]) -> int:
    if not paths:
        return 0
    if not Path(YAMLLINT_CONFIG).is_file():
        return 0
    result = subprocess.run(
        ["yamllint", "-c", YAMLLINT_CONFIG, *paths],
        capture_output=True, text=True,
    )
    count = 0
    for line in result.stdout.splitlines():
        stripped = line.lstrip()
        if not stripped or stripped == line:
            continue
        head = stripped.split(" ", 1)[0]
        if ":" in head and all(part.isdigit() for part in head.split(":", 1)):
            count += 1
    return count


def count_broken_links(pkg_dir: Path) -> int:
    count = 0
    for root, dirs, files in os.walk(pkg_dir, followlinks=False):
        for name in files + dirs:
            full = Path(root) / name
            if full.is_symlink():
                try:
                    resolved = full.resolve(strict=True)
                    _ = resolved
                except (OSError, RuntimeError):
                    count += 1
    return count


def main() -> int:
    ap = argparse.ArgumentParser(description="Mechanical-hygiene audit (γ-2)")
    ap.add_argument("--package-dir", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=False)
    args = ap.parse_args()

    pkg_dir = args.package_dir.resolve()
    if not pkg_dir.is_dir():
        print(f"error: {pkg_dir} not a directory", file=sys.stderr)
        return 2

    yaml_paths = collect_yaml_paths(pkg_dir)
    yaml_issues = count_yaml_issues(yaml_paths)
    broken_links = count_broken_links(pkg_dir)

    audit = {
        "package": pkg_dir.name,
        "dir": str(pkg_dir),
        "totals": {
            "yaml_issues": yaml_issues,
            "broken_links": broken_links,
        },
    }

    if args.json:
        args.json.write_text(json.dumps(audit, indent=2))
    else:
        print(json.dumps(audit, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
