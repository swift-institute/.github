#!/usr/bin/env bash
# Controls for assemble.jq: exhausted clone failures are UNMEASURED, never failing, never passing, and keep the certificate non-green and incomplete.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
failures=0
run() {
  jq -sc --arg date d --arg run r --argjson parked '["o/parked"]' --argjson partial "${2:-false}" \
    --argjson shards "$1" --arg image i --arg xcode x --argjson advisory "${3:-[]}" -f "$here/assemble.jq"
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
check "missing: counted as unmeasured" 2 "$(jq .counts.unmeasured <<<"$out")"
check "missing: listed as unmeasured" '["o/b linux","o/b macos"]' "$(jq -c '.unmeasured' <<<"$out")"
check "missing: cause named" '"no result: the shard produced no row for this repository"' "$(jq -c '.unmeasuredCauses[0].cause' <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass ""; row o/b linux pass pass pass "") | run '[{"repositories":"o/a"},{"repositories":"o/b"}]')"
check "lost macOS shard: green" false "$(jq .green <<<"$out")"
check "lost macOS shard: unmeasured" '["o/b macos"]' "$(jq -c '.unmeasured' <<<"$out")"
check "lost macOS shard: failing" 0 "$(jq .counts.failing <<<"$out")"

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

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass ""; row o/a windows pass fail skip "x"; row o/b windows clone-failed skip skip "fatal") | run '[{"repositories":"o/a"}]' false '["windows"]')"
check "advisory windows failure: still green" 'true' "$(jq -c '.green' <<<"$out")"
check "advisory windows failure: gating counts exclude it" '2' "$(jq -c '.counts.results' <<<"$out")"
check "advisory windows failure: listed under advisory" '["o/a windows"]' "$(jq -c '.advisory.windows.failing' <<<"$out")"
check "advisory windows clone failure: unmeasured under advisory" '["o/b windows"]' "$(jq -c '.advisory.windows.unmeasured' <<<"$out")"
check "advisory windows rows: kept in results" '4' "$(jq -c '.results | length' <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass ""; row o/b linux pass pass pass ""; row o/b macos pass pass pass ""; row o/a windows pass pass pass "") | run "$shards" false '["windows"]')"
check "advisory windows missing row: unmeasured under advisory" '["o/b windows"]' "$(jq -c '.advisory.windows.unmeasured' <<<"$out")"
check "advisory windows missing row: gating still green" 'true' "$(jq -c '.green' <<<"$out")"

out="$( (row o/a linux pass pass pass ""; row o/a macos pass pass pass ""; row o/b linux pass pass pass ""; row o/b macos pass pass pass ""; row o/a windows pass pass pass ""; row o/b windows excluded skip skip "platforms: apple,linux") | run "$shards" false '["windows"]')"
check "excluded windows row: not failing" '[]' "$(jq -c '.advisory.windows.failing' <<<"$out")"
check "excluded windows row: not unmeasured" '[]' "$(jq -c '.advisory.windows.unmeasured' <<<"$out")"
check "excluded windows row: counted" '1' "$(jq -c '.advisory.windows.counts.excluded' <<<"$out")"

[ "$failures" -eq 0 ] || { echo "$failures control(s) failed"; exit 1; }
echo "all assemble controls passed"
