#!/usr/bin/env bash
# Controls for assemble.jq: exhausted clone failures are UNMEASURED, never failing, never passing, and keep the certificate non-green and incomplete.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
failures=0
run() {
  jq -sc --arg date d --arg run r --argjson parked '["o/parked"]' --argjson partial "${2:-false}" \
    --argjson shards "$1" --arg image i --arg xcode x -f "$here/assemble.jq"
}
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1: $3"; else echo "FAIL $1: expected $2, got $3"; failures=$((failures + 1)); fi
}
row() { printf '{"repository":"%s","platform":"%s","sha":"s","resolve":"%s","build":"%s","test":"%s","cause":"%s","provisioned":""}\n' "$@"; }
shards='[{"repositories":"o/a o/b"}]'

out="$(row o/a linux pass pass pass "" | cat - <(row o/a macos pass pass pass "" ; row o/b linux pass pass skip ""; row o/b macos pass pass pass "") | run "$shards")"
check "all pass: green" true "$(jq .green <<<"$out")"
check "all pass: complete" true "$(jq .complete <<<"$out")"
check "all pass: unmeasured" 0 "$(jq .counts.unmeasured <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos clone-failed skip skip "fatal: unable to access"; row o/b linux pass pass pass ""; row o/b macos pass pass pass "") | run "$shards")"
check "clone exhausted only: green" false "$(jq .green <<<"$out")"
check "clone exhausted only: complete" false "$(jq .complete <<<"$out")"
check "clone exhausted only: failing" 0 "$(jq .counts.failing <<<"$out")"
check "clone exhausted only: unmeasured" 1 "$(jq .counts.unmeasured <<<"$out")"
check "clone exhausted only: unmeasured row" '"o/a macos"' "$(jq -c '.unmeasured[0]' <<<"$out")"
check "clone exhausted only: not counted as pass" 0 "$(jq '[.results[] | select(.resolve == "clone-failed" and .build == "pass")] | length' <<<"$out")"

out="$( (row o/a linux fail skip skip "o/dep"; row o/a macos clone-failed skip skip "fatal"; row o/b linux pass pass pass ""; row o/b macos pass pass pass "") | run "$shards")"
check "mixed: failing" 1 "$(jq .counts.failing <<<"$out")"
check "mixed: unmeasured" 1 "$(jq .counts.unmeasured <<<"$out")"
check "mixed: green" false "$(jq .green <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass "") | run "$shards")"
check "missing: green" false "$(jq .green <<<"$out")"
check "missing: complete" false "$(jq .complete <<<"$out")"
check "missing: missing" 2 "$(jq .counts.missing <<<"$out")"

out="$( (row o/parked linux clone-failed skip skip "fatal") | run '[{"repositories":"o/parked"}]')"
check "parked clone failure: unmeasured" 0 "$(jq .counts.unmeasured <<<"$out")"

out="$(: | run '[]')"
check "empty input: green" false "$(jq .green <<<"$out")"
check "empty input: complete" false "$(jq .complete <<<"$out")"
check "empty input: results" 0 "$(jq .counts.results <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass "") | run '[{"repositories":"o/a"}]' true)"
check "partial scope all pass: green" false "$(jq .green <<<"$out")"
check "partial scope all pass: complete" false "$(jq .complete <<<"$out")"
check "partial scope all pass: partial" true "$(jq .partial <<<"$out")"

[ "$failures" -eq 0 ] || { echo "$failures control(s) failed"; exit 1; }
echo "all assemble controls passed"
