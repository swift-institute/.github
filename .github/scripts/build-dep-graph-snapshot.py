#!/usr/bin/env python3
"""
Build a GitHub dependency-graph snapshot from a SwiftPM package.

Reads `swift package show-dependencies --format json` output and the
package's git context (sha, ref) and emits a snapshot JSON suitable for
POSTing to `/repos/<owner>/<repo>/dependency-graph/snapshots`.

Snapshot schema reference:
  https://docs.github.com/en/rest/dependency-graph/dependency-submission

Usage:
  swift package show-dependencies --format json > /tmp/deps.json
  GITHUB_SHA=$(git rev-parse HEAD) \
  GITHUB_REF=refs/heads/main \
  GITHUB_RUN_ID=12345 \
  build-dep-graph-snapshot.py /tmp/deps.json > /tmp/snapshot.json

Outputs JSON to stdout. The caller is expected to POST this to the
GitHub API:

  gh api -X POST repos/<owner>/<repo>/dependency-graph/snapshots \
    --input /tmp/snapshot.json
"""

import json
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse


def to_purl(url: str, version: str | None) -> str:
    """
    Convert a SwiftPM dep's git URL + resolved version to a Package URL.

    Format: pkg:swift/<host>/<owner>/<repo>@<version>

    Per https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst#swift,
    the swift purl type uses the source repo URL as the qualifier path. We use
    `host/owner/repo` as the namespace+name. Version is the resolved git ref —
    a tag like "1.2.3" if the dep is tag-pinned, or a commit SHA for branch-
    pinned (Swift Institute's branch-main pinning convention).
    """
    parsed = urlparse(url.rstrip("/"))
    host = parsed.netloc or "github.com"
    path = parsed.path.lstrip("/")
    if path.endswith(".git"):
        path = path[: -len(".git")]
    namespace_and_name = f"{host}/{path}"
    if version:
        return f"pkg:swift/{namespace_and_name}@{version}"
    return f"pkg:swift/{namespace_and_name}"


def flatten_deps(node: dict, depth: int = 0, seen: set | None = None) -> list[tuple[dict, bool]]:
    """
    Walk the swift-package-show-dependencies tree, returning a flat list of
    (dep_node, is_direct) tuples. Direct = depth==1 (depth 0 is the root
    package itself). Deduplicates by package name to avoid double-counting
    diamond deps.
    """
    if seen is None:
        seen = set()
    out = []
    for child in node.get("dependencies", []):
        name = child.get("name", "")
        if name in seen:
            # Already recorded; skip to avoid duplicate manifest entries.
            continue
        seen.add(name)
        is_direct = depth == 0
        out.append((child, is_direct))
        out.extend(flatten_deps(child, depth + 1, seen))
    return out


def build_snapshot(deps_root: dict, sha: str, ref: str, run_id: str,
                   correlator: str) -> dict:
    """Build the full snapshot JSON document."""
    resolved: dict[str, dict] = {}
    for dep, is_direct in flatten_deps(deps_root):
        name = dep.get("name", "")
        url = dep.get("url", "")
        version = dep.get("version", "")
        if not name or not url:
            continue
        purl = to_purl(url, version)
        resolved[name] = {
            "package_url": purl,
            "relationship": "direct" if is_direct else "indirect",
            "scope": "runtime",
        }
    return {
        "version": 0,
        "sha": sha,
        "ref": ref,
        "job": {
            "id": run_id,
            "correlator": correlator,
        },
        "detector": {
            "name": "swift-institute-bot dep-graph submitter",
            "url": "https://github.com/swift-institute/.github",
            "version": "0.1.0",
        },
        "scanned": datetime.now(timezone.utc).isoformat(),
        "manifests": {
            "Package.swift": {
                "name": "Package.swift",
                "file": {"source_location": "Package.swift"},
                "resolved": resolved,
            }
        },
    }


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <deps.json>", file=sys.stderr)
        return 2
    deps_path = sys.argv[1]
    try:
        with open(deps_path) as f:
            deps_root = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"error: cannot read {deps_path}: {e}", file=sys.stderr)
        return 2
    sha = os.environ.get("GITHUB_SHA", "")
    ref = os.environ.get("GITHUB_REF", "refs/heads/main")
    run_id = os.environ.get("GITHUB_RUN_ID", "0")
    correlator = os.environ.get("GITHUB_RUN_NUMBER", "swift-institute-bot")
    if not sha:
        print("error: GITHUB_SHA env var required", file=sys.stderr)
        return 2
    snapshot = build_snapshot(deps_root, sha, ref, run_id, correlator)
    json.dump(snapshot, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
