#!/usr/bin/env bash
# check-skill-descriptions.sh — verify skill `description:` frontmatter ≤ 250 chars.
#
# Mechanical enforcement of [SKILL-CREATE-013] / [SKILL-CREATE-013a] in
# swift-institute/Skills/skill-lifecycle/SKILL.md. Walks every SKILL.md under
# the given roots, extracts the YAML `description:` block, counts characters,
# and exits non-zero on any violation not in the allowlist.
#
# Usage:
#   ./Scripts/check-skill-descriptions.sh [<root>...]
#
# Arguments:
#   <root>   one or more directories containing Skills/. Defaults to the
#            standard ecosystem roots when invoked without arguments.
#
# Allowlist:
#   .skill-description-allowlist (sibling file to this script — one skill name
#   per line, # comments permitted). Skills listed here MAY exceed the 250-char
#   ceiling; each entry SHOULD have a comment naming the routing concern that
#   justifies the size.
#
# Environment:
#   SKILL_DESCRIPTION_CEILING — override the 250-char default. Tightening
#                                (e.g., 200) is encouraged; loosening should be
#                                rare and documented.
#
# Exit codes:
#   0  all skills compliant (or only allowlisted overruns).
#   1  one or more skills exceed the ceiling without an allowlist entry.
#   2  invocation error (missing dir, bad arg).
#
# This script lives in the PUBLIC `swift-institute/.github` repo so that CI
# workflows in public Skills-bearing repos can fetch it without a private-repo
# token. Free-account / no-billing constraint: the swift-institute/Scripts
# repo (where sync-skills.sh lives) MUST stay private to avoid exposing org
# tooling, but its CI script must be reachable from public-repo CI runs.
#
# Invoked by:
#   - swift-institute/Scripts/sync-skills.sh — local pre-flight gate at sync time.
#     Sync-skills lives in the private Scripts repo; it locates this script
#     via the swift-institute/.github/.github/scripts/ path on disk.
#   - .github/.github/workflows/lint-skill-descriptions.yml — CI gate. Public
#     consumer repos check out swift-institute/.github and run this script
#     against their own Skills/ tree.
#
# Provenance: 2026-05-08 long-term-hygiene cycle (see also feedback memory tombstones).

set -euo pipefail

CEILING="${SKILL_DESCRIPTION_CEILING:-250}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="${SCRIPT_DIR}/.skill-description-allowlist"

# Default roots — directories in the swift-institute ecosystem that can hold
# SKILL.md files. Override by passing explicit roots as args. CI consumers
# always pass explicit roots; defaults are convenience for ad-hoc local runs.
#
# Scope note: rule-institute is a PARALLEL institute (legal-domain) with its
# own skill discipline; it is intentionally OUTSIDE swift-institute's default
# scope. To audit rule-institute, pass its Skills root explicitly:
#   ./check-skill-descriptions.sh ~/Developer/rule-institute/Skills
DEFAULT_ROOTS=(
  "${HOME}/Developer/swift-institute/Skills"
  "${HOME}/Developer/swift-institute/Engagement/Skills"
  "${HOME}/Developer/swift-primitives/Skills"
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
  echo "::error::no skill roots found (default roots all absent; pass explicit roots as args)" >&2
  exit 2
fi

# Load allowlist into a newline-separated string (POSIX-compatible —
# macOS ships bash 3.2 which lacks `declare -A`).
ALLOWED_LIST=""
ALLOWED_COUNT=0
if [[ -f "$ALLOWLIST" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line## }"
    line="${line%% }"
    [[ -z "$line" ]] && continue
    ALLOWED_LIST="${ALLOWED_LIST}${line}
"
    ALLOWED_COUNT=$((ALLOWED_COUNT + 1))
  done < "$ALLOWLIST"
fi

# Test whether a name is allowlisted. POSIX-compatible.
is_allowed() {
  local name="$1"
  printf '%s\n' "$ALLOWED_LIST" | grep -qFx "$name"
}

# Extract the YAML description: block from a SKILL.md file and count its
# character length. Handles both block-scalar (`description: |`) and inline
# (`description: foo`) forms.
description_chars() {
  local file="$1"
  awk '
    /^description:/ { flag = 1; next }
    flag && /^[a-z_]+:/ { exit }
    flag { print }
  ' "$file" | wc -c | tr -d ' '
}

violations=0
total_skills=0
total_violations=()

for root in "${ROOTS[@]}"; do
  while IFS= read -r -d '' skill_file; do
    total_skills=$((total_skills + 1))
    skill_dir="$(dirname "$skill_file")"
    skill_name="$(basename "$skill_dir")"
    chars=$(description_chars "$skill_file")

    if (( chars > CEILING )); then
      if is_allowed "$skill_name"; then
        printf '  ALLOWED %s: %s chars (over ceiling %s, allowlisted)\n' \
          "$skill_name" "$chars" "$CEILING"
      else
        violations=$((violations + 1))
        total_violations+=("${skill_name}: ${chars} chars (over ceiling ${CEILING})")
        printf '::error file=%s::skill description %s chars exceeds ceiling %s — see [SKILL-CREATE-013]\n' \
          "$skill_file" "$chars" "$CEILING"
      fi
    fi
  done < <(find "$root" -mindepth 2 -maxdepth 3 -name 'SKILL.md' -print0 2>/dev/null)
done

echo
echo "Scanned $total_skills skill(s) across ${#ROOTS[@]} root(s)."
echo "Ceiling: $CEILING chars. Allowlist: ${ALLOWED_COUNT} entry/entries."

if (( violations > 0 )); then
  echo
  echo "VIOLATIONS ($violations):"
  printf '  - %s\n' "${total_violations[@]}"
  echo
  echo "To fix, follow [SKILL-CREATE-013]:"
  echo "  1. Cut architecture/feature enumerations from the description."
  echo "  2. Preserve routing predicates (TRIGGER/SKIP, Apply when X)."
  echo "  3. Target ≤ 250 chars."
  echo "If the skill genuinely needs a longer routing rubric, add an entry to:"
  echo "  $ALLOWLIST"
  exit 1
fi

echo "OK — all skills compliant."
exit 0
