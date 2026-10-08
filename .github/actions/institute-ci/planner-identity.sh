# Shared by Plan's seal and ci-ok's verification of the reused planner.
planner_sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }

# The full toolchain identity: every line of `swift --version`.
planner_toolchain() { swift --version 2>/dev/null; }

# The runtime identity: each Swift runtime library the executable resolves
# to, by name and content digest, or "unresolved" when it does not resolve.
planner_runtime() {
  local binary=$1 name path
  if command -v ldd >/dev/null 2>&1 && ldd "$binary" >/dev/null 2>&1; then
    ldd "$binary" | awk '/=>/ {print $1, $3}' | while read -r name path; do
      case "$name" in
        libswift*|libFoundation*|lib_Foundation*|libdispatch*|libBlocksRuntime*) ;;
        *) continue ;;
      esac
      if [ -f "$path" ]; then echo "$name $(planner_sha "$path")"; else echo "$name unresolved"; fi
    done | sort
  else
    echo "no dynamic runtime"
  fi
}

# Shared libraries the executable needs but the job does not provide.
planner_missing_libraries() {
  if command -v ldd >/dev/null 2>&1; then ldd "$1" 2>/dev/null | grep "not found" || true; fi
}
