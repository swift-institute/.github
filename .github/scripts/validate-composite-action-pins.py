#!/usr/bin/env python3
"""validate-composite-action-pins.py — [CI-117] identity-pin self-referential
composite-action references.

Programme corrigendum §11.1 (swift-institute/.github#286, ruled R4/R4a/R4b):
Section 2.11 of the Swift Institute CI/CD Refactor Programme places Institute
composite actions (`uses: <org>/<repo>/.github/actions/<name>@<ref>`) in the
**identity-pinned** class — full commit SHA, never a floating branch or tag.
This is the opposite of `[CI-030]`/`REPO-ACTIONS-004`, which require intra-
Institute **reusable workflows**
(`uses: <org>/<repo>/.github/workflows/<file>.yml@main`) to stay permanently
on `@main`. Confusing the two classes in either direction is a hard stop —
this validator enforces only the composite-action class and MUST NOT be
extended to reusable-workflow `uses:` lines.

Rule checked:
  [CI-117]  Every `uses:` reference to
            `swift-institute/.github/.github/actions/<name>@<ref>` inside
            `swift-institute/.github`'s own `.github/workflows/*.yml` MUST
            pin `<ref>` to a full 40-character lowercase-hex commit SHA.
            A branch (`@main`), a short SHA, or a tag all fire.

Scope: this checks swift-institute/.github's own workflows referencing its
own composite actions (the self-referential case named by the corrigendum —
a repository cannot pin a reference to its own tree at authoring time, so
these 34 sites needed a deliberate ruling; see #286 comments for the R4/R4a/R4b
record). It does not check third-party action pins (a different, already
covered, class) or reusable-workflow refs (permanently exempt, see above).

Typed exemption (owner, path, trigger, uses, reason, retirement condition —
ledger-style, not a wildcard): `lint-validators-weekly.yml` lines 126 and 608
(`read-orgs@main`, `upsert-tracking-issue@main`) are excluded. Owner: lane
0B-01 holds that file in flight (swift-institute/.github#295, "Replace six
oversized validator matrices with organization sweeps") under the same
programme; task 0A-04's resource-lane grant explicitly excludes it to avoid
a two-lane write collision. Trigger: any `uses:` line inside that one file
naming those two actions. Reason: cross-lane file-ownership conflict, not a
disagreement about the rule. Retirement condition: delete the exemption in
the same PR that next touches those two lines under either lane — do not
carry it forward once 0B-01's work lands and the file is free again. These
two sites emit `CI-117-EXEMPT` (informational) and do not fail the check;
every other site in the same file, and every site in every other workflow,
is fully enforced.

Usage:
  validate-composite-action-pins.py <repo-name> <repo-root>
Exit:
  1 when any non-exempt, non-40-hex-pinned self-referential composite-action
  `uses:` is found, else 0. (>=2 signals a crash / usage error, per the
  harness convention.)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

RULE = "CI-117"
RULE_EXEMPT = "CI-117-EXEMPT"

# (workflow filename, action name) -> reason. See the module docstring's
# "Typed exemption" section for the full owner/trigger/retirement record.
# Keep this set to exact (file, action) pairs — never a filename wildcard —
# so a *different* action gaining an unpinned reference in the same file
# still fires CI-117 normally.
EXEMPT: dict[tuple[str, str], str] = {
    ("lint-validators-weekly.yml", "read-orgs"): (
        "swift-institute/.github#286 resource-lane grant excludes this file; "
        "owned in flight by lane 0B-01 (swift-institute/.github#295)"
    ),
    ("lint-validators-weekly.yml", "upsert-tracking-issue"): (
        "swift-institute/.github#286 resource-lane grant excludes this file; "
        "owned in flight by lane 0B-01 (swift-institute/.github#295)"
    ),
}

# Matches: uses: swift-institute/.github/.github/actions/<name>@<ref>
# <ref> is captured raw (no anchoring) so a floating branch, a short SHA, or
# a tag are all visible in the finding message, not silently coerced.
USES_RE = re.compile(
    r"^\s*(?:-\s*)?uses:\s*"
    r"swift-institute/\.github/\.github/actions/(?P<action>[A-Za-z0-9_-]+)"
    r"@(?P<ref>\S+)\s*(?:#.*)?$"
)
FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def emit(repo: str, rule: str, message: str) -> None:
    safe = message.replace("\t", " ").replace("\n", " ")
    print(f"{repo}\t{rule}\t{safe}")


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    """Return (line_no, action, ref) for every non-SHA-pinned self-ref."""
    findings: list[tuple[int, str, str]] = []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return findings
    for i, line in enumerate(lines, start=1):
        m = USES_RE.match(line)
        if m is None:
            continue
        ref = m.group("ref")
        if FULL_SHA_RE.match(ref):
            continue
        findings.append((i, m.group("action"), ref))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("root")
    args = ap.parse_args()

    workflows_dir = Path(args.root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        # No workflows directory is not this rule's finding to make; a
        # different validator/fixture owns repository-shape absence.
        return 0

    findings = 0
    for workflow in sorted(workflows_dir.glob("*.yml")):
        for line_no, action, ref in scan_file(workflow):
            key = (workflow.name, action)
            if key in EXEMPT:
                emit(
                    args.repo,
                    RULE_EXEMPT,
                    f"{workflow.name}:{line_no}: swift-institute/.github/.github/actions/"
                    f"{action}@{ref} — exempt: {EXEMPT[key]}",
                )
                continue
            emit(
                args.repo,
                RULE,
                f"{workflow.name}:{line_no}: swift-institute/.github/.github/actions/"
                f"{action}@{ref} is not identity-pinned — Institute composite "
                f"actions (§2.11) pin to a full 40-hex commit SHA, never a "
                f"branch or tag. This is the composite-action class, distinct "
                f"from [CI-030]'s permanently-@main reusable-workflow class — "
                f"do not 'fix' this by exempting the site.",
            )
            findings += 1
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
