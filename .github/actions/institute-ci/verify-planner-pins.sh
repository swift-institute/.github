#!/usr/bin/env bash
# Contract between the planner publisher (institute-application's
# publish-planner, release `ci-binaries`) and its consumer (this action,
# which reads `.institute-ci-pin` and `.institute-ci-planner` live).
#
# Usage: verify-planner-pins.sh <.institute-ci-pin> <.institute-ci-planner>
# Env:   PLANNER_ASSET_BASE  release download base (tests point it at file://)
#
# Refuses when:
# - the pin is not exactly one 40-hex line;
# - a planner row is not `<40-hex> <platform> <64-hex> <64-hex>`, or names
#   an unknown platform;
# - the pinned revision has no row for a platform the action downloads for
#   (every fleet run on that platform would silently build from source);
# - a winning row for the pinned revision was not published: no
#   PIN-<revision>-<run> asset carries that exact line;
# - the binary or graph a winning row names is missing from the release or
#   does not hash to the row's digest.
set -euo pipefail
pin_file=$1 planner_file=$2
base=${PLANNER_ASSET_BASE:-https://github.com/swift-institute/institute-application/releases/download/ci-binaries}
platforms="linux-x86_64 macos-arm64"
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }
refuse() { echo "refused: $*" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pins="$(grep -v '^[[:space:]]*#' "$pin_file" | grep -v '^[[:space:]]*$' || true)"
[ "$(printf '%s\n' "$pins" | grep -c .)" -eq 1 ] || refuse "$pin_file must hold exactly one revision line"
revision="$pins"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || refuse "malformed pinned revision '$revision'"

rows="$work/rows"
grep -v '^[[:space:]]*#' "$planner_file" | grep -v '^[[:space:]]*$' > "$rows" || true
n=0
while read -r rev platform binary graph extra; do
  n=$((n + 1))
  [[ "$rev" =~ ^[0-9a-f]{40}$ && "$binary" =~ ^[0-9a-f]{64}$ && "$graph" =~ ^[0-9a-f]{64}$ && -z "${extra:-}" ]] \
    || refuse "malformed planner row $n: '$rev $platform $binary $graph${extra:+ $extra}'"
  case " $platforms " in *" $platform "*) ;; *) refuse "planner row $n names unknown platform '$platform'" ;; esac
done < "$rows"

# Every PIN asset published for the pinned revision; a row is admissible only
# if one of them carries it verbatim.
published="$work/published"
: > "$published"
if [ -n "${PLANNER_PUBLISHED_PINS:-}" ]; then
  cat "$PLANNER_PUBLISHED_PINS" > "$published"
else
  for asset in $(gh release view ci-binaries -R swift-institute/institute-application --json assets \
      --jq ".assets[].name | select(startswith(\"PIN-$revision-\"))"); do
    curl --fail --silent --show-error --location --retry 3 "$base/$asset" >> "$published"
    echo >> "$published"
  done
fi

for platform in $platforms; do
  row="$(awk -v r="$revision" -v p="$platform" '$1 == r && $2 == p {v = $0} END {print v}' "$rows")"
  [ -n "$row" ] || refuse "pinned revision $revision has no planner row for $platform; every $platform run would build the planner from source"
  grep -qxF "$row" "$published" || refuse "planner row for $revision $platform was not published by any PIN-$revision-* asset: '$row'"
  read -r _ _ binary graph <<< "$row"
  curl --fail --silent --show-error --location --retry 3 -o "$work/binary" "$base/institute-$platform-$binary" \
    || refuse "release has no institute-$platform-$binary"
  [ "$(sha "$work/binary")" = "$binary" ] || refuse "institute-$platform-$binary does not hash to its name"
  curl --fail --silent --show-error --location --retry 3 -o "$work/graph" "$base/Package.resolved-$platform-$graph" \
    || refuse "release has no Package.resolved-$platform-$graph"
  [ "$(sha "$work/graph")" = "$graph" ] || refuse "Package.resolved-$platform-$graph does not hash to its name"
  echo "ok: $revision $platform binary $binary graph $graph"
done
