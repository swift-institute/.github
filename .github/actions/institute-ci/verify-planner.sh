#!/usr/bin/env bash
# Verifies the planner that Plan sealed for this run before ci-ok executes it.
# usage: verify-planner.sh <sealed-dir> <binary-digest> <manifest-digest> <workflow-sha> <sources-revision> <subject-sha>
# The digests and revisions are Plan's job outputs. GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT,
# RUNNER_OS and RUNNER_ARCH come from the job environment.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/planner-identity.sh"
dir=$1 digest=$2 manifest_digest=$3 workflow=$4 sources=$5 subject=$6
manifest="$dir/manifest.json"
binary="$dir/institute"
graph="$dir/Package.resolved"
refuse() { echo "::error::planner reuse refused: $*"; exit 1; }
field() { jq -r --arg key "$1" '.[$key] // "" | tostring' "$manifest" 2>/dev/null; }
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || refuse "Plan published no planner digest"
[[ "$manifest_digest" =~ ^[0-9a-f]{64}$ ]] || refuse "Plan published no manifest digest"
[ -f "$manifest" ] || refuse "the sealed manifest is missing"
[ "$(planner_sha "$manifest")" = "$manifest_digest" ] || refuse "the sealed manifest differs from the one Plan published"
jq -e 'type == "object"' "$manifest" >/dev/null 2>&1 || refuse "the sealed manifest is not a JSON object"
[ -f "$binary" ] || refuse "the sealed planner binary is missing"
[ -f "$graph" ] || refuse "the sealed planner graph is missing"
[ "$(field run)" = "${GITHUB_RUN_ID:-}" ] || refuse "sealed for run '$(field run)', not this run '${GITHUB_RUN_ID:-}'"
[ "$(field attempt)" = "${GITHUB_RUN_ATTEMPT:-}" ] || refuse "sealed for attempt '$(field attempt)', not this attempt '${GITHUB_RUN_ATTEMPT:-}'"
[ "$(field os)" = "${RUNNER_OS:-}" ] || refuse "sealed on '$(field os)', not '${RUNNER_OS:-}'"
[ "$(field arch)" = "${RUNNER_ARCH:-}" ] || refuse "sealed for '$(field arch)', not '${RUNNER_ARCH:-}'"
[ "$(field workflow)" = "$workflow" ] || refuse "sealed at workflow '$(field workflow)', not '$workflow'"
[ "$(field sources)" = "$sources" ] || refuse "sealed from planner sources '$(field sources)', not '$sources'"
[ "$(field subject)" = "$subject" ] || refuse "sealed for subject '$(field subject)', not '$subject'"
toolchain="$(planner_toolchain)"
[ -n "$toolchain" ] && [ "$(field toolchain)" = "$toolchain" ] || refuse "sealed with a different toolchain than this job's: $(field toolchain | head -1) vs $(head -1 <<< "$toolchain")"
[ "$(field digest)" = "$digest" ] || refuse "the manifest's binary digest differs from Plan's"
[ "$(planner_sha "$binary")" = "$digest" ] || refuse "the sealed binary's digest differs from Plan's"
[ "$(planner_sha "$graph")" = "$(field graph)" ] || refuse "the sealed graph's digest differs from the manifest"
chmod +x "$binary"
missing="$(planner_missing_libraries "$binary")"
[ -z "$missing" ] || refuse "the job does not provide the planner's libraries: $missing"
[ "$(field runtime)" = "$(planner_runtime "$binary")" ] || refuse "the job's Swift runtime differs from the one the planner was sealed with"
"$binary" --help >/dev/null 2>&1 || refuse "the restored planner does not launch"
echo "planner reuse verified: $digest (manifest $manifest_digest), run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT}, ${RUNNER_OS}/${RUNNER_ARCH}, subject $subject, sources $sources"
