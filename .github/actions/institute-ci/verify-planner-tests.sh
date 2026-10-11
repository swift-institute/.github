#!/usr/bin/env bash
# Positive and negative controls for seal-planner.sh and verify-planner.sh.
# Exit 0 only if every control behaves.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/planner-identity.sh"
work="$(mktemp -d)"
mkdir -p "$work/bin" "$work/other"
printf '#!/usr/bin/env bash\necho "Swift version 6.4 (control)"\necho "Target: x86_64-unknown-linux-gnu"\n' > "$work/bin/swift"
printf '#!/usr/bin/env bash\necho "Swift version 6.4 (control)"\necho "Target: aarch64-unknown-linux-gnu"\n' > "$work/other/swift"
chmod +x "$work/bin/swift" "$work/other/swift"
export PATH="$work/bin:$PATH" GITHUB_RUN_ID=1001 GITHUB_RUN_ATTEMPT=1 RUNNER_OS=Linux RUNNER_ARCH=X64
WORKFLOW=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SOURCES=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SUBJECT=cccccccccccccccccccccccccccccccccccccccc
seal() {
  local src="$work/src-$1"
  mkdir -p "$src/.build/release"
  printf '#!/usr/bin/env bash\n[ "$1" = --help ] && exit 0\nexit 3\n' > "$src/.build/release/institute"
  echo '{"pins":[]}' > "$src/Package.resolved"
  bash "$here/seal-planner.sh" "$src/.build/release/institute" "$work/$1" "$SOURCES" "$WORKFLOW" "$SUBJECT" > "$work/$1.out"
  chmod -x "$work/$1/institute"
  DIGEST=$(sed -n 's/^digest=//p' "$work/$1.out")
  MDIGEST=$(sed -n 's/^manifest-digest=//p' "$work/$1.out")
  DIR="$work/$1"
}
rewrite() { jq "$2" "$1/manifest.json" > "$work/m" && mv "$work/m" "$1/manifest.json"; }
failures=0
expect() {
  local want=$1 name=$2; shift 2
  local status=0
  ( "$@" ) > "$work/out" 2>&1 || status=$?
  if { [ "$want" = pass ] && [ "$status" -eq 0 ]; } || { [ "$want" = fail ] && [ "$status" -ne 0 ]; }; then
    echo "control $name: $want (exit $status) $(grep -o "refused: .*" "$work/out" | head -1 | cut -c1-90)"
  else
    echo "CONTROL BROKEN $name: wanted $want, exit $status"; cat "$work/out"; failures=$((failures + 1))
  fi
}
verify() { bash "$here/verify-planner.sh" "$@"; }
seal ok; expect pass "matching seal" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nodigest; expect fail "Plan published no binary digest" verify "$DIR" "" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nomdigest; expect fail "Plan published no manifest digest" verify "$DIR" "$DIGEST" "" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nomanifest; rm "$DIR/manifest.json"; expect fail "missing manifest" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal badmanifest; echo '[' > "$DIR/manifest.json"; expect fail "malformed manifest" verify "$DIR" "$DIGEST" "$(planner_sha "$DIR/manifest.json")" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nobinary; rm "$DIR/institute"; expect fail "missing binary" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal norun; expect fail "wrong run" env GITHUB_RUN_ID=999 bash "$here/verify-planner.sh" "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal noattempt; expect fail "wrong attempt" env GITHUB_RUN_ATTEMPT=2 bash "$here/verify-planner.sh" "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal noos; expect fail "wrong platform os" env RUNNER_OS=macOS bash "$here/verify-planner.sh" "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal noarch; expect fail "wrong platform arch" env RUNNER_ARCH=ARM64 bash "$here/verify-planner.sh" "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nowf; expect fail "wrong workflow revision" verify "$DIR" "$DIGEST" "$MDIGEST" dddddddddddddddddddddddddddddddddddddddd "$SOURCES" "$SUBJECT"
seal nosrc; expect fail "wrong planner sources" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee "$SUBJECT"
seal nosubject; expect fail "wrong subject" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" ffffffffffffffffffffffffffffffffffffffff
seal notc; expect fail "different toolchain in this job" env PATH="$work/other:$PATH" bash "$here/verify-planner.sh" "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal mdiff; expect fail "manifest digest differs from Plan's" verify "$DIR" "$DIGEST" "$(printf 'f%.0s' {1..64})" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal pair; echo '{"pins":[1]}' > "$DIR/Package.resolved"; rewrite "$DIR" ".graph = \"$(planner_sha "$DIR/Package.resolved")\""; expect fail "rewritten manifest and graph pair" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal runtime; rewrite "$DIR" '.runtime = "libswiftCore.so 0000"'; expect fail "different runtime identity" verify "$DIR" "$DIGEST" "$(planner_sha "$DIR/manifest.json")" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal tamper; echo '# replaced' >> "$DIR/institute"; expect fail "replaced binary" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal graph; echo '{"pins":[1]}' > "$DIR/Package.resolved"; expect fail "replaced graph" verify "$DIR" "$DIGEST" "$MDIGEST" "$WORKFLOW" "$SOURCES" "$SUBJECT"
seal nolaunch; printf '#!/usr/bin/env bash\nexit 3\n' > "$DIR/institute"; D2=$(planner_sha "$DIR/institute"); rewrite "$DIR" ".digest = \"$D2\""; expect fail "planner does not launch" verify "$DIR" "$D2" "$(planner_sha "$DIR/manifest.json")" "$WORKFLOW" "$SOURCES" "$SUBJECT"
[ "$failures" -eq 0 ] || { echo "$failures control(s) broken"; exit 1; }
echo "all planner reuse controls behave"
