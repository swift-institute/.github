#!/usr/bin/env bash
# Verifies the planner that Plan sealed for this run before ci-ok executes it.
# usage: verify-planner.sh <sealed-dir> <digest-from-plan> <workflow-sha-from-plan> <sources-revision-from-plan>
# Reads GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, RUNNER_OS and RUNNER_ARCH from the job environment.
set -euo pipefail
dir=$1 digest=$2 workflow=$3 sources=$4
manifest="$dir/manifest.json"
binary="$dir/institute"
graph="$dir/Package.resolved"
refuse() { echo "::error::planner reuse refused: $*"; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }
field() { jq -r --arg key "$1" '.[$key] // "" | tostring' "$manifest" 2>/dev/null; }
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || refuse "Plan published no planner digest"
[ -f "$manifest" ] || refuse "the sealed manifest is missing"
jq -e 'type == "object"' "$manifest" >/dev/null 2>&1 || refuse "the sealed manifest is not a JSON object"
[ -f "$binary" ] || refuse "the sealed planner binary is missing"
[ -f "$graph" ] || refuse "the sealed planner graph is missing"
[ "$(field run)" = "${GITHUB_RUN_ID:-}" ] || refuse "sealed for run '$(field run)', not this run '${GITHUB_RUN_ID:-}'"
[ "$(field attempt)" = "${GITHUB_RUN_ATTEMPT:-}" ] || refuse "sealed for attempt '$(field attempt)', not this attempt '${GITHUB_RUN_ATTEMPT:-}'"
[ "$(field os)" = "${RUNNER_OS:-}" ] || refuse "sealed on '$(field os)', not '${RUNNER_OS:-}'"
[ "$(field arch)" = "${RUNNER_ARCH:-}" ] || refuse "sealed for '$(field arch)', not '${RUNNER_ARCH:-}'"
[ "$(field workflow)" = "$workflow" ] || refuse "sealed at workflow '$(field workflow)', not '$workflow'"
[ "$(field sources)" = "$sources" ] || refuse "sealed from planner sources '$(field sources)', not '$sources'"
toolchain="$(swift --version 2>/dev/null | head -1 || true)"
[ -n "$toolchain" ] && [ "$(field toolchain)" = "$toolchain" ] || refuse "sealed with toolchain '$(field toolchain)', not '$toolchain'"
[ "$(field digest)" = "$digest" ] || refuse "the manifest digest '$(field digest)' differs from Plan's '$digest'"
[ "$(sha "$binary")" = "$digest" ] || refuse "the sealed binary's digest differs from Plan's '$digest'"
[ "$(sha "$graph")" = "$(field graph)" ] || refuse "the sealed graph's digest differs from the manifest"
chmod +x "$binary"
"$binary" --help >/dev/null 2>&1 || refuse "the restored planner does not launch"
echo "planner reuse verified: $digest, run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT}, ${RUNNER_OS}/${RUNNER_ARCH}, sources $sources"
