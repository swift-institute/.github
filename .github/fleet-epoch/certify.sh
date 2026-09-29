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
  if git clone --quiet --depth 1 "https://github.com/$repository.git" "$directory" >>"$log" 2>&1; then
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
  printf '{"repository":"%s","platform":"%s","sha":"%s","resolve":"%s","build":"%s","test":"%s"}\n' \
    "$repository" "$platform" "$sha" "$resolve" "$build" "$test" >>"$output"
  echo "$repository $platform resolve=$resolve build=$build test=$test"
done
