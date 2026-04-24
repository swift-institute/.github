#!/usr/bin/env python3
# Patch an umbrella module's symbol graph with doc comments from sibling
# module graphs. Emits the patched umbrella graph (plus any @-suffixed
# umbrella extension graphs) to an isolated output directory suitable for
# xcrun docc convert --additional-symbol-graph-dir.
#
# Canonical pipeline per `swift-institute/Research/docc-multi-target-
# documentation-aggregation.md` R3 and the `documentation` skill's
# [DOC-019a]:
#
#     swift build -c release \
#         -Xswiftc -emit-symbol-graph \
#         -Xswiftc -emit-symbol-graph-dir -Xswiftc <raw-dir>
#
#     python3 patch-umbrella-symbol-graph.py \
#         --symbol-graph-dir <raw-dir> \
#         --umbrella-module <Umbrella_Module> \
#         --output-dir <umbrella-only-dir>
#         [--exclude-module <Name> ...]
#
#     xcrun docc convert <umbrella.docc> \
#         --additional-symbol-graph-dir <umbrella-only-dir> \
#         --fallback-display-name "<Umbrella>" \
#         --fallback-bundle-identifier <bundle-id> \
#         --output-path <out.doccarchive>
#
# Two roles:
#
#   1. Doc-comment injection. Walk every non-umbrella graph, build a map
#      from `identifier.precise` (USR) to its `docComment`, and inject any
#      missing docComment into the umbrella graph's matching symbol. Under
#      `swift build -emit-symbol-graph` this patches zero symbols in
#      practice (the emitter preserves @_exported re-export doc comments
#      natively); retained as a defensive no-op in case a future Swift
#      release regresses the behaviour.
#
#   2. Umbrella-graph isolation. Writes ONLY the patched umbrella graph —
#      plus any `<Umbrella>@<OtherModule>.symbols.json` extension graphs
#      that belong to the umbrella — to the output directory. Isolation is
#      load-bearing: passing the full graph pool to `docc convert` causes
#      cross-module reference ambiguity (the same USR appears under both
#      the declaring module and the umbrella), breaking in-catalog
#      `` `Symbol` `` spans.
#
# The script is stdlib-only. It is platform-agnostic, runs under any
# Python 3.8+, and makes no network or filesystem assumptions beyond the
# two directories it is told about.

import argparse
import json
import os
import sys
from pathlib import Path


def collect_doc_comments(symbol_graph_paths, umbrella_module):
    """Build USR -> docComment map from every non-umbrella graph."""
    usr_to_doc_comment = {}
    for path in symbol_graph_paths:
        name = path.name
        module_prefix = name.split("@", 1)[0].rsplit(".symbols.json", 1)[0]
        if module_prefix == umbrella_module:
            continue
        with path.open() as f:
            graph = json.load(f)
        for symbol in graph.get("symbols", []):
            doc_comment = symbol.get("docComment")
            if not doc_comment or not doc_comment.get("lines"):
                continue
            usr = symbol.get("identifier", {}).get("precise")
            if not usr:
                continue
            usr_to_doc_comment.setdefault(usr, doc_comment)
    return usr_to_doc_comment


def patch_graph(graph, usr_to_doc_comment):
    """Inject missing docComments into graph's symbols; return (graph, patched_count)."""
    patched = 0
    for symbol in graph.get("symbols", []):
        existing = symbol.get("docComment")
        if existing and existing.get("lines"):
            continue
        usr = symbol.get("identifier", {}).get("precise")
        if not usr:
            continue
        replacement = usr_to_doc_comment.get(usr)
        if replacement is None:
            continue
        symbol["docComment"] = replacement
        patched += 1
    return graph, patched


def umbrella_graph_paths(symbol_graph_dir, umbrella_module):
    """Return the umbrella's primary graph plus any @-suffixed extension graphs."""
    prefix = f"{umbrella_module}.symbols.json"
    ext_prefix = f"{umbrella_module}@"
    results = []
    for path in sorted(symbol_graph_dir.iterdir()):
        name = path.name
        if not name.endswith(".symbols.json"):
            continue
        if name == prefix or name.startswith(ext_prefix):
            results.append(path)
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Patch the umbrella symbol graph with doc comments from sibling "
            "graphs and isolate it into a dedicated output directory."
        ),
    )
    parser.add_argument(
        "--symbol-graph-dir",
        required=True,
        type=Path,
        help="Directory of per-module symbol graphs (swift build output).",
    )
    parser.add_argument(
        "--umbrella-module",
        required=True,
        help="Umbrella module name (underscore form, e.g. Property_Primitives).",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Destination for the patched, isolated umbrella graph(s).",
    )
    parser.add_argument(
        "--exclude-module",
        action="append",
        default=[],
        help=(
            "Module prefix to exclude when collecting doc comments (e.g. a "
            "test-support module). May be passed multiple times."
        ),
    )
    args = parser.parse_args(argv)

    symbol_graph_dir = args.symbol_graph_dir.resolve()
    output_dir = args.output_dir.resolve()
    umbrella = args.umbrella_module
    excludes = set(args.exclude_module)

    if not symbol_graph_dir.is_dir():
        print(
            f"error: --symbol-graph-dir {symbol_graph_dir} is not a directory",
            file=sys.stderr,
        )
        return 2

    all_graphs = sorted(
        p for p in symbol_graph_dir.iterdir()
        if p.is_file() and p.name.endswith(".symbols.json")
    )
    if not all_graphs:
        print(f"error: no *.symbols.json files in {symbol_graph_dir}", file=sys.stderr)
        return 2

    donor_graphs = [
        p for p in all_graphs
        if p.name.split("@", 1)[0].rsplit(".symbols.json", 1)[0] not in excludes
    ]

    umbrella_files = umbrella_graph_paths(symbol_graph_dir, umbrella)
    if not umbrella_files:
        print(
            f"error: no symbol graph found for umbrella module {umbrella!r} in {symbol_graph_dir}",
            file=sys.stderr,
        )
        return 2

    usr_to_doc_comment = collect_doc_comments(donor_graphs, umbrella)

    output_dir.mkdir(parents=True, exist_ok=True)
    # Clean any stale graphs from a prior run.
    for stale in output_dir.glob("*.symbols.json"):
        stale.unlink()

    total_patched = 0
    for source in umbrella_files:
        with source.open() as f:
            graph = json.load(f)
        graph, patched = patch_graph(graph, usr_to_doc_comment)
        total_patched += patched
        destination = output_dir / source.name
        with destination.open("w") as f:
            json.dump(graph, f)

    print(
        f"patched {total_patched} symbol(s) across {len(umbrella_files)} "
        f"umbrella graph file(s); wrote to {output_dir}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
