#!/usr/bin/env python3
"""validate-package-graph.py — [MOD-032] package-graph acyclicity.

Rules checked:
  [MOD-032]       Package dependencies MUST be acyclic at the PACKAGE-graph
                  level, not merely the target-graph level. SwiftPM tolerates
                  target-acyclic/package-cyclic configurations; the institute
                  forbids them ("works today by accident" is not timeless).
  [PRIM-ARCH-002] (corollary, swift-primitives org) Downward-only tier deps.
                  Tiers are COMPUTED algorithmically from the dependency
                  graph (Documentation.docc/Primitives Tiers.md), so the
                  tier ordering exists iff the graph is acyclic — this
                  validator IS the rule's mechanical content. Findings inside
                  the swift-primitives org cite both IDs.

Detection: regex-parse every Package.swift under <repo-root> (recursive,
pruned), build the package graph (path deps resolve to on-disk dirs; url
deps to identities), and report every strongly-connected component of size
≥ 2 (full cycle detection — the in-rule 2-cycle audit script under-detects
longer cycles). Edges point only at packages present in the scanned set, so
run the sweep over the WORKSPACE root to catch cross-org cycles.

Baseline: sibling `.package-graph-baseline` — prune-only; each line is a
sorted `<member>+<member>+…` cycle key with a provenance comment. The known
live memory↔storage cycle ships baselined (fixing it is ADT/tower-arc
terrain per HANDOFF-mechanization-arc Do-Not-Touch). Baselined cycles are
reported as `(baselined)` and do not count as findings.

Output: TSV findings `repo<TAB>MOD-032<TAB>message` (validate_lib.emit).

Usage:
  validate-package-graph.py <repo-name> <repo-root> [<extra-root> ...]
  (extra roots union into one graph — pass the org dirs together to catch
  cross-org cycles without sweeping out-of-scope trees)

Provenance: REPORT-corpus-review.md §5 NONE batch, promoted via /promote-rule
per HANDOFF-mechanization-arc W1. Outcome records:
swift-institute/Audits/PROMOTE-MOD-032-2026-07-06.md (+ the PRIM-ARCH-002
covered-by disposition record).
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from validate_lib import emit

RULE = "MOD-032"

# coenttb is the workspace's hard scope exclusion (never grep/consume);
# swiftlang is the upstream toolchain checkout; fixtures/Fixtures are
# synthetic manifest trees (incl. this validator's own harness fixtures).
SKIP_DIRS = {".build", ".git", ".swiftpm", ".claude", "node_modules",
             "checkouts", ".trash", "Library", "coenttb", "swiftlang",
             "fixtures", "Fixtures"}

RE_URL_DEP = re.compile(r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?url:\s*"([^"]+)"')
RE_PATH_DEP = re.compile(r'\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"([^"]+)"')


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def url_repo_name(url: str) -> str:
    last = url.rstrip("/").rsplit("/", 1)[-1]
    return last[:-4] if last.endswith(".git") else last


def manifests(root: Path):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "Package.swift" in filenames:
            found.append(Path(dirpath) / "Package.swift")
    return sorted(found)


def build_graph(root: Path) -> dict[str, set[str]]:
    """{package-node → dep-nodes}. Nodes are lower-cased dir basenames for
    on-disk packages; url identities for remote deps. Edges are kept only
    when the target node is itself in the scanned set (cycles need both
    ends on disk)."""
    graph: dict[str, set[str]] = {}
    for m in manifests(root):
        node = m.parent.name.lower()
        text = strip_comments(m.read_text(encoding="utf-8", errors="replace"))
        deps = set()
        for url in RE_URL_DEP.findall(text):
            deps.add(url_repo_name(url).lower())
        for rel in RE_PATH_DEP.findall(text):
            deps.add((m.parent / rel).resolve().name.lower())
        deps.discard(node)  # nested-test-package self edges are not cycles
        graph.setdefault(node, set()).update(deps)
    # Edge restriction to scanned nodes happens AFTER multi-root union (main).
    return graph


def sccs(graph: dict[str, set[str]]):
    """Iterative Tarjan; yields strongly-connected components of size ≥ 2
    (plus size-1 self-loop components, which build_graph already excludes)."""
    index: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    on_stack: set[str] = set()
    stack: list[str] = []
    counter = [0]
    result = []

    for start in sorted(graph):
        if start in index:
            continue
        work = [(start, iter(sorted(graph[start])))]
        index[start] = lowlink[start] = counter[0]
        counter[0] += 1
        stack.append(start)
        on_stack.add(start)
        while work:
            node, it = work[-1]
            advanced = False
            for nxt in it:
                if nxt not in index:
                    index[nxt] = lowlink[nxt] = counter[0]
                    counter[0] += 1
                    stack.append(nxt)
                    on_stack.add(nxt)
                    work.append((nxt, iter(sorted(graph[nxt]))))
                    advanced = True
                    break
                if nxt in on_stack:
                    lowlink[node] = min(lowlink[node], index[nxt])
            if advanced:
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                lowlink[parent] = min(lowlink[parent], lowlink[node])
            if lowlink[node] == index[node]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == node:
                        break
                if len(comp) >= 2:
                    result.append(sorted(comp))
    return result


def load_baseline(script_dir: Path) -> set[str]:
    path = script_dir / ".package-graph-baseline"
    out = set()
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(line)
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(f"usage: {Path(argv[0]).name} <repo-name> <repo-root> [<extra-root> ...]",
              file=sys.stderr)
        return 2
    repo, roots = argv[1], [Path(p) for p in argv[2:]]
    for r in roots:
        if not r.is_dir():
            print(f"# error: root not found: {r}", file=sys.stderr)
            return 2

    graph: dict[str, set[str]] = {}
    for r in roots:
        for node, deps in build_graph(r).items():
            graph.setdefault(node, set()).update(deps)
    nodes = set(graph)
    graph = {n: {d for d in deps if d in nodes} for n, deps in graph.items()}
    baseline = load_baseline(Path(__file__).resolve().parent)

    for comp in sccs(graph):
        key = "+".join(comp)
        if key in baseline:
            print(f"# baselined cycle (not a finding): {' <-> '.join(comp)}")
            continue
        prim = all(n.endswith("-primitives") for n in comp)
        cite = "MOD-032 + PRIM-ARCH-002" if prim else "MOD-032"
        emit(repo, RULE,
             f"package-level cycle: {' <-> '.join(comp)} ({cite}; SwiftPM may "
             f"tolerate it at target level — still forbidden; break the cycle "
             f"or baseline with provenance)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
