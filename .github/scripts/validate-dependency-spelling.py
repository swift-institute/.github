#!/usr/bin/env python3
"""validate-dependency-spelling.py — [PKG-DEP-009] canonical dependency-URL spelling.

Manifest-only lint (regex over Package*.swift at the repo root; no build, no
resolve; sub-second).

Rule checked: [PKG-DEP-009] — every `.package(url:)` in an institute manifest
MUST spell the dependency as `https://github.com/<org>/<repo>.git` (exact
`.git`-suffixed form), and MUST NOT use `.package(path:)` or a retired-org
spelling. SwiftPM's mirror substitution is an EXACT-STRING lookup and its
canonical-location comparison treats every distinct spelling of one package
identity as a distinct location: one bare (or historical-org) spelling next
to a mirrored `.git` spelling puts the same identity under two canonical
locations, which fires the conflicting-identity branch in
`createResolvedPackages` — on SwiftPM 6.2+ that branch enumerates every
distinct dependency path (exponential; an effective hang on institute-scale
graphs). One divergent edge suffices. Dossier:
swift-institute/Issues/swift-issue-spm-identity-conflict-path-enumeration-hang/
(catalog §A26).

Checks:
  V1  bare GitHub URL (missing `.git` suffix)
  V2  `.package(path:)` in a committed manifest (leaks machine-local layout;
      local-path resolution is the mirror table's job)
  V3  retired/foreign-org spelling (`coenttb/`, `swift-web-standards/`) —
      these orgs' packages live under institute orgs now; old spellings
      belong to immutable historical tags only, never to live manifests

Output: TSV findings `repo<TAB>PKG-DEP-009<TAB>message` (validate_lib.emit).
Exit 0 always (findings are counted by the harness / aggregation layer).

Usage:
  validate-dependency-spelling.py <repo-name> <repo-root>

Companions: Scripts/scan-identity-conflicts.py (fleet-wide divergence scan,
mirror-context aware) and Scripts/normalize-dependency-spellings.py (the
mechanical fixer) in the private Scripts repo.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from validate_lib import emit

RULE = "PKG-DEP-009"

# Repos whose findings are documented known-exceptions: reported with the
# -EXEMPT rule tag (informational; the aggregation layer counts only exact
# PKG-DEP-009 rows). swift-html-prism is untouchable by standing rule
# (HANDOFF-spm-hang-resolution-2026-07-10; normalize-dependency-spellings.py
# carries the same skip) — its pointfreeco/coenttb spellings are a known,
# accepted edge until its owning arc addresses the repo.
KNOWN_EXCEPTIONS = {
    "swift-foundations/swift-html-prism": "untouchable by standing rule (hang-arc handoff); known mixed edge",
}

RETIRED_ORGS = ("coenttb", "swift-web-standards")

RE_URL_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?url:\s*"(?P<url>[^"]+)"'
)
RE_PATH_DEP = re.compile(
    r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"(?P<path>[^"]+)"'
)
RE_MANIFEST = re.compile(r"Package(@swift-[\d.]+)?\.swift")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo_name, root = sys.argv[1], Path(sys.argv[2])

    exemption = KNOWN_EXCEPTIONS.get(repo_name) or KNOWN_EXCEPTIONS.get(repo_name.split("/")[-1])
    rule = f"{RULE}-EXEMPT" if exemption else RULE
    if exemption:
        emit(repo_name, rule, f"known-exception repo ({exemption}); findings below are informational")

    for manifest in sorted(root.glob("Package*.swift")):
        if not RE_MANIFEST.fullmatch(manifest.name):
            continue
        try:
            text = manifest.read_text(errors="replace")
        except OSError:
            continue
        for m in RE_URL_DEP.finditer(text):
            url = m.group("url")
            gh = re.match(r"https://github\.com/([^/]+)/([^/]+?)(\.git)?$", url)
            if gh is None:
                if url.startswith(("http://", "git@")):
                    emit(repo_name, rule, f"{manifest.name}: non-canonical URL form `{url}` — use https://github.com/<org>/<repo>.git")
                continue
            org = gh.group(1)
            if org in RETIRED_ORGS:
                emit(repo_name, rule, f"{manifest.name}: retired-org spelling `{url}` — repoint to the package's current institute org (.git form)")
                continue
            if not gh.group(3):
                emit(repo_name, rule, f"{manifest.name}: bare URL `{url}` — append `.git` (exact-spelling uniformity keeps one canonical location per identity)")
        for m in RE_PATH_DEP.finditer(text):
            emit(repo_name, rule, f"{manifest.name}: `.package(path: \"{m.group('path')}\")` — committed manifests use canonical URLs; local resolution belongs to the mirror table")
    return 0


if __name__ == "__main__":
    sys.exit(main())
