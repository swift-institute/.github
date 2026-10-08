#!/usr/bin/env bash
# Positive and negative controls for verify-planner.sh. Exit 0 only if every control behaves.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\necho "Swift version 6.4 (control)"\n' > "$work/bin/swift"
chmod +x "$work/bin/swift"
export PATH="$work/bin:$PATH" GITHUB_RUN_ID=1001 GITHUB_RUN_ATTEMPT=1 RUNNER_OS=Linux RUNNER_ARCH=X64
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }
WORKFLOW=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SOURCES=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
seal() {
  local dir="$work/$1"; mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n[ "$1" = --help ] && exit 0\nexit 3\n' > "$dir/institute"
  echo '{"pins":[]}' > "$dir/Package.resolved"
  jq -n --arg digest "$(sha "$dir/institute")" --arg graph "$(sha "$dir/Package.resolved")" \
    --arg workflow "$WORKFLOW" --arg sources "$SOURCES" \
    '{run:"1001", attempt:"1", os:"Linux", arch:"X64", toolchain:"Swift version 6.4 (control)", sources:$sources, workflow:$workflow, subject:"cccc", digest:$digest, graph:$graph}' > "$dir/manifest.json"
  chmod -x "$dir/institute"
  echo "$dir"
}
failures=0
expect() {
  local want=$1 name=$2; shift 2
  local status=0
  ( "$@" ) > "$work/out" 2>&1 || status=$?
  if { [ "$want" = pass ] && [ "$status" -eq 0 ]; } || { [ "$want" = fail ] && [ "$status" -ne 0 ]; }; then
    echo "control $name: $want (exit $status)"
  else
    echo "CONTROL BROKEN $name: wanted $want, exit $status"; cat "$work/out"; failures=$((failures + 1))
  fi
}
verify() { bash "$here/verify-planner.sh" "$@"; }
d=$(seal ok); expect pass "matching seal" verify "$d" "$(jq -r .digest "$d/manifest.json")" "$WORKFLOW" "$SOURCES"
d=$(seal nodigest); expect fail "Plan published no digest" verify "$d" "" "$WORKFLOW" "$SOURCES"
d=$(seal nomanifest); D=$(jq -r .digest "$d/manifest.json"); rm "$d/manifest.json"; expect fail "missing manifest" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal badmanifest); D=$(jq -r .digest "$d/manifest.json"); echo '[' > "$d/manifest.json"; expect fail "malformed manifest" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal nobinary); D=$(jq -r .digest "$d/manifest.json"); rm "$d/institute"; expect fail "missing binary" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal norun); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong run" env GITHUB_RUN_ID=999 bash "$here/verify-planner.sh" "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal noattempt); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong attempt" env GITHUB_RUN_ATTEMPT=2 bash "$here/verify-planner.sh" "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal noos); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong platform os" env RUNNER_OS=macOS bash "$here/verify-planner.sh" "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal noarch); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong platform arch" env RUNNER_ARCH=ARM64 bash "$here/verify-planner.sh" "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal nowf); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong workflow revision" verify "$d" "$D" dddddddddddddddddddddddddddddddddddddddd "$SOURCES"
d=$(seal nosrc); D=$(jq -r .digest "$d/manifest.json"); expect fail "wrong planner sources" verify "$d" "$D" "$WORKFLOW" eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
d=$(seal notc); D=$(jq -r .digest "$d/manifest.json"); jq '.toolchain = "Swift version 6.3 (other)"' "$d/manifest.json" > "$work/m" && mv "$work/m" "$d/manifest.json"; expect fail "wrong toolchain" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal mdigest); D=$(jq -r .digest "$d/manifest.json"); expect fail "manifest digest differs from Plan" verify "$d" "$(printf 'f%.0s' {1..64})" "$WORKFLOW" "$SOURCES"
d=$(seal tamper); D=$(jq -r .digest "$d/manifest.json"); echo '# replaced' >> "$d/institute"; expect fail "replaced binary" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal graph); D=$(jq -r .digest "$d/manifest.json"); echo '{"pins":[1]}' > "$d/Package.resolved"; expect fail "replaced graph" verify "$d" "$D" "$WORKFLOW" "$SOURCES"
d=$(seal nolaunch); printf '#!/usr/bin/env bash\nexit 3\n' > "$d/institute"; jq --arg digest "$(sha "$d/institute")" '.digest = $digest' "$d/manifest.json" > "$work/m" && mv "$work/m" "$d/manifest.json"; expect fail "planner does not launch" verify "$d" "$(sha "$d/institute")" "$WORKFLOW" "$SOURCES"
[ "$failures" -eq 0 ] || { echo "$failures control(s) broken"; exit 1; }
echo "all planner reuse controls behave"
