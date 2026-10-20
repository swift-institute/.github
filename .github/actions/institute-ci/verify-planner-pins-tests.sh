#!/usr/bin/env bash
# Positive and negative controls for verify-planner-pins.sh, offline: the
# release is a file:// directory and the published PIN assets a local file.
# Exit 0 only if every control behaves.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }
REV=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OLD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# A release holding one published planner per platform.
release() {
  rm -rf "$work/release"; mkdir -p "$work/release"
  : > "$work/published"
  for p in linux-x86_64 macos-arm64; do
    printf 'binary %s\n' "$p" > "$work/b"; printf '{"pins":["%s"]}\n' "$p" > "$work/g"
    B=$(sha "$work/b"); G=$(sha "$work/g")
    cp "$work/b" "$work/release/institute-$p-$B"; cp "$work/g" "$work/release/Package.resolved-$p-$G"
    echo "$REV $p $B $G" >> "$work/published"
  done
  printf '# comment\n%s\n' "$REV" > "$work/pin"
  { echo "# rows"; echo "$OLD linux-x86_64 $(printf 'c%.0s' {1..64}) $(printf 'd%.0s' {1..64})"; cat "$work/published"; } > "$work/planner"
}
row() { grep " $1 " "$work/published"; }

failures=0
expect() {
  local want=$1 name=$2; shift 2
  local status=0
  ( "$@" ) > "$work/out" 2>&1 || status=$?
  if { [ "$want" = pass ] && [ "$status" -eq 0 ]; } || { [ "$want" = fail ] && [ "$status" -ne 0 ]; }; then
    echo "control $name: $want (exit $status) $(grep -o "refused: .*" "$work/out" | head -1 | cut -c1-100)"
  else
    echo "CONTROL BROKEN $name: wanted $want, exit $status"; cat "$work/out"; failures=$((failures + 1))
  fi
}
verify() {
  PLANNER_ASSET_BASE="file://$work/release" PLANNER_PUBLISHED_PINS="$work/published" \
    bash "$here/verify-planner-pins.sh" "$work/pin" "$work/planner"
}

release; expect pass "published rows for both platforms" verify
release; echo "$REV linux-x86_64 $(printf 'e%.0s' {1..64}) $(printf 'f%.0s' {1..64})" > "$work/x"
  cat "$work/planner" "$work/x" > "$work/p2"; cp "$work/p2" "$work/planner"; cat "$work/x" >> "$work/published"
  expect fail "last row wins and names a missing binary" verify
release; cat "$work/planner" > "$work/p2"; row linux-x86_64 >> "$work/p2"; cp "$work/p2" "$work/planner"
  expect pass "a repeated published row" verify
release; grep -v ' macos-arm64 ' "$work/planner" > "$work/p2"; cp "$work/p2" "$work/planner"
  expect fail "pinned revision without a macos-arm64 row" verify
release; printf '%s\n' "$OLD" > "$work/pin"; expect fail "pin names a revision with no rows" verify
release; printf '%s\n%s\n' "$REV" "$OLD" > "$work/pin"; expect fail "two pin lines" verify
release; printf 'main\n' > "$work/pin"; expect fail "pin is not a revision" verify
release; echo "$REV linux-x86_64 short $(printf 'd%.0s' {1..64})" >> "$work/planner"; expect fail "malformed digest" verify
release; echo "$REV windows-x86_64 $(printf 'c%.0s' {1..64}) $(printf 'd%.0s' {1..64})" >> "$work/planner"; expect fail "unknown platform" verify
release; echo "$(row macos-arm64) extra" >> "$work/planner"; expect fail "trailing field" verify
release; grep -v ' macos-arm64 ' "$work/published" > "$work/p2"; cp "$work/p2" "$work/published"
  expect fail "row typed by hand, never published" verify
release; read -r _ _ B _ <<< "$(row linux-x86_64)"; echo tampered >> "$work/release/institute-linux-x86_64-$B"
  expect fail "replaced binary" verify
release; read -r _ _ _ G <<< "$(row macos-arm64)"; rm "$work/release/Package.resolved-macos-arm64-$G"
  expect fail "missing graph" verify

[ "$failures" -eq 0 ] || { echo "$failures control(s) broken"; exit 1; }
echo "all controls behave"
