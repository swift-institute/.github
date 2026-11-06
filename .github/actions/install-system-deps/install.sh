#!/usr/bin/env bash
# Usage: install.sh <manifest>...
# Scans the given manifests for .linkedLibrary("<name>"), maps each name to its
# apt -dev package, installs the missing ones, and prints the provisioned
# packages (space-separated) on stdout. Diagnostics go to stderr. A no-op on
# runners without apt-get.
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "no apt-get (non-Debian runner) — skipping system-dep derivation" >&2
  exit 0
fi

libs=$(grep -hoE '\.linkedLibrary\("[^"]+"' "$@" 2>/dev/null \
       | sed -E 's/.*"([^"]+)".*/\1/' | sort -u || true)
echo "Linked libraries in dependency graph: ${libs:-<none>}" >&2

# Map a linker name to its apt -dev package. Libraries shipped by libc6-dev
# (already in the toolchain image) map to the empty string; an unknown library
# returns __UNMAPPED__ so the caller can warn.
map_lib() {
  case "$1" in
    uuid)     echo uuid-dev ;;
    uring)    echo liburing-dev ;;
    z)        echo zlib1g-dev ;;
    ssl|crypto) echo libssl-dev ;;
    curl)     echo libcurl4-openssl-dev ;;
    sqlite3)  echo libsqlite3-dev ;;
    xml2)     echo libxml2-dev ;;
    c|dl|m|pthread|rt|util|resolv) echo "" ;;
    *)        echo __UNMAPPED__ ;;
  esac
}

pkgs=""
for lib in $libs; do
  p=$(map_lib "$lib")
  if [ "$p" = "__UNMAPPED__" ]; then
    echo "::warning::No apt mapping for linked library '$lib'. If its header is needed at compile time, add it to map_lib in swift-institute/.github install-system-deps." >&2
  elif [ -n "$p" ]; then
    pkgs="$pkgs $p"
  fi
done

# A system library target names its apt packages itself: GRDB's GRDBSQLite has
# providers: [.apt(["libsqlite3-dev"])] and links through its module map, with no
# .linkedLibrary to find. Only a package map_lib already knows is installed, so a
# dependency's manifest can't choose what goes on the runner.
known=" uuid-dev liburing-dev zlib1g-dev libssl-dev libcurl4-openssl-dev libsqlite3-dev libxml2-dev "
declared=$(grep -hoE '\.apt\(\[[^]]*\]' "$@" 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | sort -u || true)
echo "Declared apt providers in dependency graph: ${declared:-<none>}" >&2
for p in $declared; do
  case "$known" in
    *" $p "*) pkgs="$pkgs $p" ;;
    *) echo "::warning::Apt provider '$p' is not in install.sh's known packages. If it is needed at compile time, add it." >&2 ;;
  esac
done

pkgs=$(printf '%s\n' $pkgs | sort -u | tr '\n' ' ')
if [ -z "${pkgs// }" ]; then
  echo "No system dev-packages required." >&2
  exit 0
fi

missing=""
for p in $pkgs; do
  dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done
if [ -n "${missing// }" ]; then
  echo "Installing system dev-packages:$missing" >&2
  apt-get update -qq >&2
  apt-get install -qq -y $missing >&2
fi
echo "${pkgs% }"
