#!/usr/bin/env bash
# check-canon.sh — canon guard for the skill rulebook (markdown corpus).
#
# The rulebook checks itself: five checks over the skill corpora verifying
# referential integrity of the canon — the layer the 2026-07-05 corpus review
# proved rots when unguarded (8 fatal cross-rule contradictions, ~30 dangling
# references, every one in unguarded prose). NOT a swift-linter rule:
# swift-linter parses Swift source; this family reads the markdown rulebook.
#
# Checks (engine: check-canon.py, same dir):
#   1. citations      [ID] cites resolve (heading / table-row registry /
#                     sub-label registry forms; ranges by endpoints; wildcards)
#   2. duplicates     one canonical definition site per ID, mirrors allowlisted
#                     per [SKILL-CREATE-016]
#   3. artifacts      cited workspace paths exist or are aspirational-tensed
#                     per [SKILL-LIFE-027]
#   4. hub-index      companions named from SKILL.md; companion IDs visible
#                     from the hub ([SKILL-CREATE-005a] criterion 4)
#   5. last-reviewed  [SKILL-LIFE-005] drift: git mtime vs last_reviewed + 1d
#
# Usage:
#   ./check-canon.sh [--enforce] [--check <name>]... [--emit-baseline]
#
# Roots: the unified three (institute Skills / Engagement Skills /
# rule-institute Skills) + Workspace/CLAUDE.md, per the 2026-07-05
# gate-root unification ruling.
#
# Modes:
#   report-only (default) — findings printed, exit 0. This is the script's
#   default flag behavior, NOT how it is wired.
#   --enforce — exit 1 on any non-baselined finding. THIS IS THE WIRED MODE:
#   sync-skills.sh invokes --enforce and aborts the sync on any non-baselined
#   finding. The explicit principal YES that the W0 constraint required before
#   flipping the wiring (HANDOFF-mechanization-arc) was given 2026-07-06 and
#   the flip has landed; the constraint is satisfied, not pending.
#
# Baseline (the ratchet): .check-canon-baseline (sibling) — prune-only, same
# contract as .skill-size-baseline. Allowlist: .check-canon-allowlist
# (sanctioned duplicate mirrors per [SKILL-CREATE-016]).
#
# Exit codes:
#   0  clean, report-only, or --emit-baseline.
#   1  non-baselined findings under --enforce.
#   2  invocation error (no corpus found, missing python3).
#
# This script lives in the PUBLIC `swift-institute/.github` repo (same
# free-account CI-reachability constraint as check-skill-sizes.sh).
#
# Invoked by:
#   - swift-institute/Scripts/sync-skills.sh — BLOCKING --enforce step at sync
#     time (principal YES 2026-07-06); a non-baselined finding aborts the sync
#     before any symlink work.
#
# Provenance: HANDOFF-mechanization-arc.md W0 (principal direction 2026-07-06);
# REPORT-corpus-review.md (2026-07-05).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null 2>&1 || {
    echo "::error::check-canon: python3 not found" >&2
    exit 2
}

DEV="$(cd "${SCRIPT_DIR}/../../.." && cd .. && pwd)"

ARGS=(
    --root "institute=${DEV}/swift-institute/Skills"
    --root "engagement=${DEV}/swift-institute/Engagement/Skills"
    --root "rule=${DEV}/rule-institute/Skills"
    --dev-root "${DEV}"
)

WORKSPACE_CLAUDE="${DEV}/swift-institute/Workspace/CLAUDE.md"
[ -f "$WORKSPACE_CLAUDE" ] && ARGS+=(--file "workspace:CLAUDE.md=${WORKSPACE_CLAUDE}")

exec python3 "${SCRIPT_DIR}/check-canon.py" "${ARGS[@]}" "$@"
