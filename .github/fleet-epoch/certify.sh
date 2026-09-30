#!/usr/bin/env bash
set -uo pipefail

platform="$1"
output="$2"
shift 2

bounded() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null; then
    gtimeout "$seconds" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
  fi
}

verdict() {
  if "$@" >>"$log" 2>&1; then echo pass; else echo fail; fi
}

export GIT_TERMINAL_PROMPT=0
work="$(mktemp -d)"
logs="$PWD/logs"
mkdir -p "$(dirname "$output")" "$logs"
: >"$output"

for repository in "$@"; do
  directory="$work/$repository"
  log="$logs/${platform}__${repository//\//__}.log"
  : >"$log"
  sha=""
  resolve=skip
  build=skip
  test=skip
  if git clone --quiet --depth 1 "https://github.com/$repository.git" "$directory" >>"$log" 2>&1 \
    || { sleep 30; git clone --quiet --depth 1 "https://github.com/$repository.git" "$directory" >>"$log" 2>&1; }; then
    sha="$(git -C "$directory" rev-parse HEAD)"
    if [ -f "$directory/Package.swift" ]; then
      scratch="$work/build"
      resolve="$(cd "$directory" && verdict bounded 900 swift package resolve --scratch-path "$scratch")"
      if [ "$resolve" = pass ]; then
        build="$(cd "$directory" && verdict bounded 2400 swift build --scratch-path "$scratch")"
        if [ "$build" = pass ] && grep -q 'testTarget' "$directory/Package.swift"; then
          test="$(cd "$directory" && verdict bounded 900 swift test --scratch-path "$scratch")"
        fi
      fi
      rm -rf "$scratch"
    else
      resolve=not-a-package
    fi
  else
    resolve=clone-failed
  fi
  rm -rf "$directory"
  cause=""
  if [ "$resolve" = clone-failed ]; then
    cause="$(grep -m1 'fatal:' "$log")"
  fi
  if [ "$resolve" = fail ]; then
    cause="$(grep -m1 -oE 'Failed to clone repository https://github.com/[^ :]*' "$log" | sed 's#.*github.com/##; s#\.git$##')"
  fi
  if [ -z "$cause" ] && { [ "$resolve" = fail ] || [ "$build" = fail ] || [ "$test" = fail ]; }; then
    sed -E "s/$(printf '\033')\[[0-9;]*m//g" "$log" >"$log.plain"
    cause="$({ grep -E '[^ ]: error:|recorded an issue' "$log.plain"; grep -E '^error:' "$log.plain"; grep -E 'error:' "$log.plain"; } | head -1 | sed -E 's#/[^ :]*/##g' | cut -c1-200)"
    rm -f "$log.plain"
  fi
  cause="$(printf '%s' "$cause" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"repository":"%s","platform":"%s","sha":"%s","resolve":"%s","build":"%s","test":"%s","cause":"%s"}\n' \
    "$repository" "$platform" "$sha" "$resolve" "$build" "$test" "$cause" >>"$output"
  echo "$repository $platform resolve=$resolve build=$build test=$test"
done
