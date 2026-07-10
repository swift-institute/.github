#!/usr/bin/env python3
"""ci-identity-conflict-fastcheck.py — fail in seconds instead of hanging.

STAGED (not yet wired into swift-ci.yml): a pre-resolve circuit breaker for
the SwiftPM identity-conflict path-enumeration hang (dossier:
swift-institute/Issues/swift-issue-spm-identity-conflict-path-enumeration-hang/,
catalog §A26). On SwiftPM 6.2–6.3.x, one package identity reachable under two
canonical locations sends graph load into an exponential path enumeration; on
a CI runner that burns the job's full timeout. This check catches the common
divergence classes from the ROOT repo's own files — no resolve, no network,
sub-second — and fails with the exact edge named.

What it checks (fast mode — root manifests + Package.resolved only):
  1. The same identity declared/pinned under two distinct canonical locations
     (e.g. a manifest spelling `swift-standards/swift-rfc-7578` while the pin
     or another manifest spells `swift-ietf/swift-rfc-7578` — org drift).
  2. NOTE: `.git` vs bare divergence is NOT flagged here — without mirrors
     both canonicalize identically, and CI has no mirrors.json. Spelling
     hygiene is [PKG-DEP-009] (validate-dependency-spelling.py).

This is deliberately an under-approximation: transitive manifests are not
visible pre-resolve. It exists to convert the *known recurring* org-drift
class from a hung job into a 1-second failure; the job-level timeout-minutes
(landed 2026-07-10) remains the backstop for everything else.

Usage:   ci-identity-conflict-fastcheck.py <repo-root>
Exit:    0 clean; 1 divergence found (printed with sources).

Known-exception repos (never-touch, accepted edges): swift-html-prism.
"""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

KNOWN_EXCEPTION_REPOS = {"swift-html-prism"}

URL_DEP_RE = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]*"\s*,\s*)?url:\s*"([^"]+)"'
)


def canonicalize(loc: str) -> str:
    loc = loc.strip().lower()
    m = re.match(r"^[\w.-]+@([\w.-]+):(.*)$", loc)
    if m:
        loc = f"{m.group(1)}/{m.group(2)}"
    else:
        loc = re.sub(r"^[a-z+]+://", "", loc)
    loc = loc.rstrip("/")
    return loc[:-4] if loc.endswith(".git") else loc


def identity_of(loc: str) -> str:
    tail = loc.rstrip("/").rsplit("/", 1)[-1].lower()
    return tail[:-4] if tail.endswith(".git") else tail


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if root.name in KNOWN_EXCEPTION_REPOS:
        print(f"fastcheck: {root.name} is a documented known-exception repo; skipping")
        return 0

    locations: dict[str, dict[str, set]] = defaultdict(lambda: defaultdict(set))
    for mf in root.glob("Package*.swift"):
        if not re.fullmatch(r"Package(@swift-[\d.]+)?\.swift", mf.name):
            continue
        for url in URL_DEP_RE.findall(mf.read_text(errors="replace")):
            locations[identity_of(url)][canonicalize(url)].add(mf.name)
    resolved = root / "Package.resolved"
    if resolved.is_file():
        try:
            pins = json.loads(resolved.read_text()).get("pins", [])
        except (json.JSONDecodeError, OSError):
            pins = []
        for pin in pins:
            loc = pin.get("location", "")
            if loc:
                locations[identity_of(loc)][canonicalize(loc)].add("Package.resolved")

    # Manifest-vs-manifest divergence is load-fatal (both spellings enter the
    # graph). Manifest-vs-pin divergence is transient — a changed requirement
    # forces re-resolution and the pin is rewritten — so it warns, not fails
    # (it usually means "spelling was fixed, pins not yet regenerated").
    hard, soft = {}, {}
    for ident, canons in locations.items():
        if len(canons) < 2:
            continue
        manifest_canons = {c for c, srcs in canons.items() if srcs - {"Package.resolved"}}
        (hard if len(manifest_canons) >= 2 else soft)[ident] = canons

    for label, group in (("STALE-PIN divergence (warning — regenerate Package.resolved)", soft),):
        if group:
            print(f"{label}:")
            for ident, canons in sorted(group.items()):
                for canon, srcs in sorted(canons.items()):
                    print(f"  '{ident}': {canon}   [{', '.join(sorted(srcs))}]")
    if not hard:
        print(f"fastcheck: no load-fatal identity-conflict edges in {root.name or root} (root manifests + pins)")
        return 0
    print("IDENTITY-CONFLICT EDGE(S) — this graph would enter the SwiftPM 6.2/6.3 "
          "exponential path enumeration at load (catalog §A26). Fix the spelling "
          "divergence below (one canonical location per identity):")
    for ident, canons in sorted(hard.items()):
        print(f"  identity '{ident}':")
        for canon, srcs in sorted(canons.items()):
            print(f"    {canon}   [{', '.join(sorted(srcs))}]")
    return 1


if __name__ == "__main__":
    sys.exit(main())
