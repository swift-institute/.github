#!/usr/bin/env bash
# check-skill-sizes.sh — verify skill markdown files stay within the size budget.
#
# Mechanical enforcement of the skill-size discipline from
# swift-institute/Research/ecosystem-meta-setup-target-state.md §D1: a skill
# file is loaded whole into agent context, so bytes are recurring per-session
# cost; SKILL.md keeps normative content (statements, one example pair per
# rule, gotchas) and evicts rationale/changelog/extended narratives to
# Research/<skill>-skill-rationale.md style archives.
#
# Walks every .md file under each skill directory in the given roots, counts
# lines, and exits non-zero on any file over budget that has no baseline entry.
#
# Usage:
#   ./check-skill-sizes.sh [<root>...]
#
# Arguments:
#   <root>   one or more directories containing skill dirs (each skill dir
#            holds SKILL.md + optional companion .md files). Defaults to the
#            standard ecosystem roots when invoked without arguments.
#
# Baseline (the ratchet):
#   .skill-size-baseline (sibling file to this script — lines of the form
#   `<skill>/<file.md> <max-lines>`, # comments permitted). Legacy files over
#   the ceiling carry a baseline entry at their CURRENT size; entries are
#   PRUNE-ONLY — they may shrink or disappear as evictions land, never grow.
#   A file over its baseline entry fails the check (regression), so the
#   corpus can only ratchet down.
#
# Environment:
#   SKILL_SIZE_CEILING — override the default per-file ceiling (1000 lines).
#
# Exit codes:
#   0  all files within ceiling or baseline.
#   1  one or more files over budget (regression or missing baseline entry).
#   2  invocation error.
#
# This script lives in the PUBLIC `swift-institute/.github` repo (same
# free-account constraint as check-skill-descriptions.sh).
#
# Invoked by:
#   - swift-institute/Scripts/sync-skills.sh — local pre-flight gate at sync time.
#
# Provenance: meta-setup realignment R2, 2026-07-02.

set -euo pipefail

CEILING="${SKILL_SIZE_CEILING:-1000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="${SCRIPT_DIR}/.skill-size-baseline"

if [ "$#" -gt 0 ]; then
    ROOTS=("$@")
else
    DEV="$(cd "${SCRIPT_DIR}/../../.." && cd .. && pwd)"
    ROOTS=(
        "${DEV}/swift-institute/Skills"
        "${DEV}/swift-institute/Engagement/Skills"
        "${DEV}/rule-institute/Skills"
    )
fi

baseline_for() {
    # $1 = <skill>/<file.md> key; echoes budget or empty
    [ -f "$BASELINE" ] || return 0
    awk -v key="$1" '$0 !~ /^#/ && $1 == key { print $2; exit }' "$BASELINE"
}

violations=0
for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r f; do
        lines=$(wc -l < "$f" | tr -d ' ')
        rel="${f#"$root"/}"
        budget=$(baseline_for "$rel")
        limit="${budget:-$CEILING}"
        if [ "$lines" -gt "$limit" ]; then
            violations=$((violations+1))
            if [ -n "$budget" ]; then
                echo "OVER BASELINE: $rel — $lines lines > baselined $budget (regression; baseline is prune-only)"
            else
                echo "OVER BUDGET:   $rel — $lines lines > $limit (evict rationale/changelog per meta-setup §D1, or baseline with provenance)"
            fi
        fi
    done < <(find "$root" -mindepth 2 -maxdepth 2 -name '*.md' -type f | sort)
done

if [ "$violations" -eq 0 ]; then
    echo "check-skill-sizes: OK — all skill files within budget/baseline."
    exit 0
fi
echo "check-skill-sizes: $violations file(s) over budget." >&2
exit 1
