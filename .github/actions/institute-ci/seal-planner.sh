#!/usr/bin/env bash
# Seals the planner Plan built for ci-ok: binary, resolved graph and manifest.
# usage: seal-planner.sh <binary> <sealed-dir> <sources-revision> <workflow-sha> <subject-sha>
# Prints `digest=` and `manifest-digest=` lines for GITHUB_OUTPUT.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/planner-identity.sh"
binary=$1 dir=$2 sources=$3 workflow=$4 subject=$5
mkdir -p "$dir"
cp "$binary" "$dir/institute"
cp "$(dirname "$(dirname "$(dirname "$binary")")")/Package.resolved" "$dir/Package.resolved"
jq -n \
  --arg run "${GITHUB_RUN_ID:-}" --arg attempt "${GITHUB_RUN_ATTEMPT:-}" \
  --arg os "${RUNNER_OS:-}" --arg arch "${RUNNER_ARCH:-}" \
  --arg toolchain "$(planner_toolchain)" --arg runtime "$(planner_runtime "$dir/institute")" \
  --arg sources "$sources" --arg workflow "$workflow" --arg subject "$subject" \
  --arg digest "$(planner_sha "$dir/institute")" --arg graph "$(planner_sha "$dir/Package.resolved")" \
  '{run: $run, attempt: $attempt, os: $os, arch: $arch, toolchain: $toolchain, runtime: $runtime, sources: $sources, workflow: $workflow, subject: $subject, digest: $digest, graph: $graph}' \
  > "$dir/manifest.json"
echo "digest=$(planner_sha "$dir/institute")"
echo "manifest-digest=$(planner_sha "$dir/manifest.json")"
