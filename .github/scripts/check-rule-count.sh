#!/usr/bin/env bash
# check-rule-count.sh — count skill rules across heading-form AND table-row form.
#
# Mechanical recognition for [SKILL-CREATE-005c] (Linter Recognition of
# Table-Row Rules): rule-counting tooling MUST union the heading-form regex
# (`^### \[[A-Z][A-Z0-9-]*-[0-9]+[a-z]?\]`) with the table-row-form regex
# (`^\| \[[A-Z][A-Z0-9-]*-[0-9]+[a-z]?\] \|`). A counter that recognizes only
# the heading form silently undercounts skills using the catalogue variant
# sanctioned by [SKILL-CREATE-005].
#
# Usage:
#   ./check-rule-count.sh [<root>...]
#
# Exit codes:
#   0  succeeded (count emitted to stdout).
#   2  invocation error (missing dir, bad arg).
#
# Provenance: Phase 3b Batch 7 (2026-05-10).

set -euo pipefail

DEFAULT_ROOTS=(
  "${HOME}/Developer/swift-institute/Skills"
  "${HOME}/Developer/swift-primitives/Skills"
  "${HOME}/Developer/swift-primitives/swift-memory-primitives/Skills"
  "${HOME}/Developer/swift-primitives/swift-index-primitives/Skills"
)

if [[ $# -gt 0 ]]; then
  ROOTS=("$@")
else
  ROOTS=()
  for r in "${DEFAULT_ROOTS[@]}"; do
    [[ -d "$r" ]] && ROOTS+=("$r")
  done
fi

if [[ ${#ROOTS[@]} -eq 0 ]]; then
  echo "::error::no skill roots found" >&2
  exit 2
fi

# Heading-form: ^## or ^### followed by [PREFIX-NNN]
HEADING_RE='^##+ \[[A-Z][A-Z0-9-]*-[0-9]+[a-z]?\]'
# Table-row form: ^| [PREFIX-NNN] |
TABLE_RE='^\| \[[A-Z][A-Z0-9-]*-[0-9]+[a-z]?\] \|'

heading_total=0
table_total=0

for root in "${ROOTS[@]}"; do
  h=$(find "$root" -name '*.md' -exec grep -hcE "$HEADING_RE" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
  t=$(find "$root" -name '*.md' -exec grep -hcE "$TABLE_RE" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
  heading_total=$((heading_total + h))
  table_total=$((table_total + t))
done

union_total=$((heading_total + table_total))

echo "Skill rule count across ${#ROOTS[@]} root(s):"
echo "  heading-form (### [ID]): $heading_total"
echo "  table-row form  (| [ID] |): $table_total"
echo "  union (per [SKILL-CREATE-005c]): $union_total"
