#!/usr/bin/env python3
"""
validate-integrated-docs-compat.py — mechanical deletability controls for the
TEMPORARY `integrated-docs` migration input (Task 4-01,
swift-institute/.github#276, #284).

Task 4-01's Change item 7 requires "zero-use/deletion checks for the
temporary input and layer docs wrappers" so Task 5-03's removal is a
mechanical operation, not a judgement call. This script is that mechanism,
in two parts:

1. MARKER CONSISTENCY (checked live, against the checked-out universal
   workflow plus the vendored layer-wrapper snapshots under
   fixtures/wrappers/ — the same population build-verdict-inventory.py
   reads, for the same reason: this repository's own CI cannot check out
   sibling repositories). Every site that declares or forwards
   `integrated-docs` MUST carry the grep-able marker token
   `[temp-integrated-docs-4-01]` in its description/comment. A site that
   has the input but has LOST the marker (or vice versa) is exactly the
   drift that would make Task 5-03's deletion a guess instead of a `grep`.

2. LAYER-DOCS-WRAPPER-REFERENCE PREDICATE (self-tested here; run against
   the real ~550-repository caller population by Task 5-02/5-03, which
   have the live caller inventory this repository does not). Given one
   package caller's `ci.yml` text, `references_legacy_docs_wrapper()`
   answers whether it still carries a separate `docs:` job calling a
   `swift-docs.yml` wrapper directly — the exact fact Task 5-03 needs
   "zero remaining legacy callers" to mean something mechanical rather
   than asserted. `test-validate-integrated-docs-compat.py` proves this
   predicate distinguishes a legacy two-job caller from a migrated
   one-job caller, so the function transported to Task 5-03 is not
   untested at handoff.

No numbered [CI-NNN] rule ID is claimed here (no /promote-rule pilot slot);
findings use the classes MARKER-MISSING / MARKER-ORPHANED.

Usage:
  python3 .github/scripts/validate-integrated-docs-compat.py \
      --universal .github/workflows/swift-ci.yml \
      --wrapper primitives=<path> --wrapper standards=<path> --wrapper foundations=<path>
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from validate_lib import emit, require_yaml

yaml = require_yaml()

MARKER = "[temp-integrated-docs-4-01]"

# The exact input name this marker travels with. A file may legitimately
# have neither (an ordinary caller has no `integrated-docs` key at all);
# the finding fires only on a MISMATCH between the two.
INPUT_NAME = "integrated-docs"


def _has_input_declaration(text: str) -> bool:
    """True if the file's `on.workflow_call.inputs` mapping declares
    `integrated-docs` (universal: the real input; layer wrapper: the
    pass-through declaration)."""
    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        return False
    on_block = doc.get("on", doc.get(True))
    if not isinstance(on_block, dict):
        return False
    wc = on_block.get("workflow_call")
    if not isinstance(wc, dict):
        return False
    inputs = wc.get("inputs")
    return isinstance(inputs, dict) and INPUT_NAME in inputs


def _has_marker(text: str) -> bool:
    return MARKER in text


def check_marker_consistency(label: str, text: str) -> int:
    """MARKER-MISSING: the input is declared but the deletion-tracking
    marker is absent (Task 5-03 would have nothing to `grep` for).
    MARKER-ORPHANED: the marker is present but the input it names is gone
    (a stale comment naming a site Task 5-03 already reached, or a marker
    added to a file that never got the actual input — either way a false
    "still needs deletion" signal)."""
    findings = 0
    has_input = _has_input_declaration(text)
    has_marker = _has_marker(text)
    if has_input and not has_marker:
        emit(
            label,
            "MARKER-MISSING",
            f"declares the `{INPUT_NAME}` input but carries no "
            f"`{MARKER}` marker — Task 5-03's mechanical deletion grep "
            f"would not find this site.",
        )
        findings += 1
    if has_marker and not has_input:
        emit(
            label,
            "MARKER-ORPHANED",
            f"carries the `{MARKER}` marker but no longer declares the "
            f"`{INPUT_NAME}` input — either a stale comment (delete it) "
            f"or the input was removed without its marker, which would "
            f"make Task 5-03's grep overcount remaining sites.",
        )
        findings += 1
    return findings


# ---------------------------------------------------------------------------
# Layer-docs-wrapper-reference predicate. Transported to Task 5-03, which
# runs it against the live ~550-repository caller population; this repo's
# own suite proves it distinguishes the two shapes on synthetic fixtures
# (test-validate-integrated-docs-compat.py), since no such population is
# reachable from here.
# ---------------------------------------------------------------------------

_DOCS_JOB_USES_SWIFT_DOCS = re.compile(
    r"^\s+uses:\s+[\w.-]+/\.github/\.github/workflows/swift-docs\.yml@",
    re.MULTILINE,
)


def references_legacy_docs_wrapper(caller_text: str) -> bool:
    """True if a package `ci.yml`'s text carries a `docs:` job whose
    `uses:` targets a layer's `swift-docs.yml` wrapper directly — the
    legacy (pre-migration) shape Task 5-02 removes when it flips a caller
    onto `integrated-docs: true`. A migrated caller (single `ci:` job,
    `integrated-docs: true`, no separate `docs:` job) returns False.

    Job-scoped: only a `docs:` job counts, not any stray comment mentioning
    swift-docs.yml (e.g. this repository's own header prose) — same
    indentation-tracked job iteration validate-thin-callers.py uses,
    reproduced narrowly rather than imported to keep this script runnable
    standalone against files outside a Package.swift-rooted checkout
    (validate-thin-callers.py's iter_jobs has no such constraint itself,
    but importing a sibling script by hyphenated filename for one function
    is more coupling than this narrow regex needs).
    """
    doc = yaml.safe_load(caller_text)
    if not isinstance(doc, dict):
        return False
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        return False
    docs_job = jobs.get("docs")
    if not isinstance(docs_job, dict):
        return False
    uses = docs_job.get("uses", "")
    return bool(_DOCS_JOB_USES_SWIFT_DOCS.search(f"  uses: {uses}"))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--universal", required=True, type=Path)
    parser.add_argument(
        "--wrapper", action="append", default=[],
        help="layer=path, repeatable (e.g. primitives=/path/to/swift-ci.yml)",
    )
    args = parser.parse_args(argv)

    findings = 0
    findings += check_marker_consistency(
        "swift-institute/.github (universal swift-ci.yml)",
        args.universal.read_text(encoding="utf-8"),
    )
    for item in args.wrapper:
        layer, _, path_str = item.partition("=")
        if not layer or not path_str:
            parser.error(f"--wrapper expects layer=path, got {item!r}")
        text = Path(path_str).read_text(encoding="utf-8")
        findings += check_marker_consistency(f"{layer} layer wrapper", text)

    if findings == 0:
        print(
            "integrated-docs-compat: marker consistency OK across the "
            "universal workflow and all declared layer wrappers.",
            file=sys.stderr,
        )
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
