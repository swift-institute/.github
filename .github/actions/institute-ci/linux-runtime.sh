#!/usr/bin/env bash
# Prints the directory holding the selected Swift toolchain's Linux runtime
# libraries (libswiftCore.so and its siblings), or fails when there is none.
# A planner that links the Swift runtime dynamically loads it from here when
# the runner image does not provide a system runtime.
set -euo pipefail
swift_bin="$(command -v swift)" || { echo "::error::no swift on PATH" >&2; exit 1; }
usr="$(cd "$(dirname "$(readlink -f "$swift_bin")")/.." && pwd -P)"
dir="$usr/lib/swift/linux"
[ -f "$dir/libswiftCore.so" ] || { echo "::error::no libswiftCore.so under $dir" >&2; exit 1; }
printf '%s\n' "$dir"
