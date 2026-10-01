#!/usr/bin/env bash
# Transitional paired-source checks for .github/actions/institute-ci.
# Every check fails closed: a missing, malformed or mismatched value exits
# nonzero with an ::error:: line. No check is skipped on missing input.
set -euo pipefail

STAGES="${INSTITUTE_CI_STATE:-${RUNNER_TEMP:-/tmp}/institute-ci-state}"

fail() { echo "::error::$*" >&2; exit 1; }
hex40() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
hex64() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
# Commission end: no pair authority may extend beyond this instant.
DEADLINE="2026-10-13T19:23:03Z"
# Production always reads the real clock. Offline tests source this file
# and redefine now_utc; no environment variable can override it.
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# canonical_utc <timestamp>: calendar-validates and round-trips, or fails.
canonical_utc() {
  python3 - "$1" <<'PY'
import sys, datetime
s = sys.argv[1]
try:
    d = datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    sys.exit(1)
if d.strftime("%Y-%m-%dT%H:%M:%SZ") != s:
    sys.exit(1)
print(s)
PY
}
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d ' ' -f 1; else shasum -a 256 "$1" | cut -d ' ' -f 1; fi; }

# stage <name> <started|ok>: append-only stage log for provenance.
stage() { mkdir -p "$STAGES"; printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$STAGES/stages"; }
# note <key> <value>: public-safe provenance value (identities and digests only).
note() { mkdir -p "$STAGES"; printf '%s=%s\n' "$1" "$2" >> "$STAGES/notes"; }

# read-pair <file>: validates the six entries and the exact UTC expiry, then
# prints them as KEY=VALUE for the caller (clock: now_utc, real in production).
read_pair() {
  local file="$1" entries now
  entries="$(grep -v '^[[:space:]]*#' "$file" | tr -d '\r' | grep -v '^[[:space:]]*$' || true)"
  [ -n "$entries" ] || return 0
  value() { printf '%s\n' "$entries" | sed -n "s/^$1=//p"; }
  [ "$(printf '%s\n' "$entries" | wc -l | tr -d ' ')" = 7 ] || fail ".institute-ci-pair must hold exactly seven entries."
  [[ "$(value pins)" =~ ^[1-9][0-9]*$ ]] || fail ".institute-ci-pair pins is not a positive count."
  for k in application application-tree institute institute-tree; do
    hex40 "$(value "$k")" || fail ".institute-ci-pair $k is not 40 lowercase hex."
  done
  hex64 "$(value resolved-sha256)" || fail ".institute-ci-pair resolved-sha256 is not 64 lowercase hex."
  local expires; expires="$(value expires)"
  canonical_utc "$expires" >/dev/null || fail ".institute-ci-pair expires '$expires' is not a real UTC timestamp YYYY-MM-DDTHH:MM:SSZ."
  [[ ! "$expires" > "$DEADLINE" ]] || fail ".institute-ci-pair expires $expires is beyond the commission end $DEADLINE."
  now="$(now_utc)"
  canonical_utc "$now" >/dev/null || fail "runtime clock '$now' is not a valid UTC timestamp."
  [[ "$now" < "$expires" ]] || fail ".institute-ci-pair expired at $expires (now $now); the pair must be removed and the normal pin used."
  for k in application application-tree institute institute-tree resolved-sha256 pins expires; do printf '%s=%s\n' "$k" "$(value "$k")"; done
}

# verify-subject <mode> <repository> <sha> <plan-result> <workspace> <app-tree> <institute-tree>
#   mode=subject:   the workspace is the ci-subject checkout. Identity must be
#                   well formed, the checkout HEAD must equal the trusted SHA,
#                   and a paired repository must present exactly the approved tree.
#   mode=aggregate: the workspace is the .github policy checkout. The trusted
#                   plan result must be stated; when it is success the plan's
#                   subject identity must be well formed (its binding already
#                   passed in plan). A non-success plan proceeds only so the
#                   unchanged aggregate can record the failure verdict.
verify_subject() {
  local mode="$1" repo="$2" sha="$3" plan_result="$4" ws="$5" app_tree="$6" inst_tree="$7"
  case "$mode" in
    subject)
      [[ "$repo" =~ ^swift-institute/[A-Za-z0-9._-]+$|^swift-[a-z0-9-]+/[A-Za-z0-9._-]+$ ]] || fail "subject repository '$repo' is missing or malformed."
      hex40 "$sha" || fail "subject SHA '$sha' is missing or malformed."
      [ -n "$ws" ] && git -C "$ws" rev-parse --git-dir >/dev/null 2>&1 || fail "no subject checkout at '$ws'."
      local head tree expected=""
      head="$(git -C "$ws" rev-parse HEAD)"
      [ "$head" = "$sha" ] || fail "subject checkout HEAD '$head' is not the trusted subject SHA '$sha'."
      tree="$(git -C "$ws" rev-parse 'HEAD^{tree}')"
      case "$repo" in
        swift-institute/institute) expected="$inst_tree" ;;
        swift-institute/institute-application) expected="$app_tree" ;;
      esac
      note subject-repository "$repo"; note subject-sha "$sha"; note subject-tree "$tree"
      if [ -n "$expected" ]; then
        [ "$tree" = "$expected" ] || fail "subject $repo tree '$tree' differs from the paired planner's approved tree '$expected'."
      fi
      ;;
    aggregate)
      case "$plan_result" in
        success)
          [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || fail "plan succeeded but its subject repository '$repo' is missing or malformed."
          hex40 "$sha" || fail "plan succeeded but its subject SHA '$sha' is missing or malformed." ;;
        failure|cancelled|skipped) ;;
        *) fail "aggregate mode requires the trusted plan result; got '$plan_result'." ;;
      esac
      note plan-result "$plan_result"; note subject-repository "${repo:-absent}"; note subject-sha "${sha:-absent}"
      ;;
    *) fail "paired planner requires subject-mode 'subject' or 'aggregate'; got '$mode'." ;;
  esac
}

# verify-graph <package-dir> <approved-resolved-sha256> <institute-revision> <institute-tree>
# Binds the ACTUAL resolved graph to the approved authority: Package.resolved
# must be byte-identical to the reviewed file, and every checkout must sit at
# its pinned revision with a clean tree; institute must carry the paired tree.
verify_graph() {
  local dir="$1" approved="$2" inst_rev="$3" inst_tree="$4" expected="$5" observed rows
  [[ "$expected" =~ ^[1-9][0-9]*$ ]] || fail "expected pin count '$expected' is missing or malformed."
  [ -f "$dir/Package.resolved" ] || fail "no Package.resolved in $dir."
  observed="$(sha256 "$dir/Package.resolved")"
  note package-resolved-sha256 "$observed"
  [ "$observed" = "$approved" ] || fail "resolved graph drifted: Package.resolved sha256 $observed is not the approved $approved."
  rows="$(mktemp)"
  jq -er '.pins | if type == "array" then .[] else error("pins is not an array") end
          | [.identity, .kind, .location, .state.revision] | @tsv' "$dir/Package.resolved" > "$rows" \
    || fail "could not parse the pins of $dir/Package.resolved."
  local n; n="$(grep -c . "$rows" || true)"
  note graph-pins "$n"
  [ "$n" = "$expected" ] || fail "resolved graph has $n pins, not the approved $expected."
  [ -z "$(cut -f 1 "$rows" | sort | uniq -d)" ] || fail "resolved graph has duplicate identities."
  local bad=0 identity kind location revision
  while IFS=$'\t' read -r identity kind location revision; do
    if [ -z "$identity" ] || [ -z "$location" ]; then echo "::error::graph row with empty identity or location" >&2; bad=1; continue; fi
    case "$kind" in remoteSourceControl|localSourceControl) ;; *) echo "::error::$identity has unexpected kind '$kind'" >&2; bad=1; continue ;; esac
    hex40 "$revision" || { echo "::error::$identity has malformed revision '$revision'" >&2; bad=1; continue; }
    local name="${location%/}"; name="${name##*/}"; name="${name%.git}"
    local co="$dir/.build/checkouts/$name" head
    if [ ! -d "$co" ]; then echo "::error::checkout for $identity missing at $co" >&2; bad=1; continue; fi
    head="$(git -C "$co" rev-parse HEAD 2>/dev/null || echo absent)"
    [ "$head" = "$revision" ] || { echo "::error::$identity checkout at $head, approved $revision" >&2; bad=1; }
    [ -z "$(git -C "$co" status --porcelain 2>/dev/null)" ] || { echo "::error::$identity checkout is dirty" >&2; bad=1; }
  done < "$rows"
  grep -q "^institute"$'\t' "$rows" || { echo "::error::approved graph has no institute pin" >&2; bad=1; }
  [ "$bad" = 0 ] || fail "resolved checkouts do not match the approved graph."
  local t; t="$(git -C "$dir/.build/checkouts/institute" rev-parse 'HEAD^{tree}')"
  note institute-checkout-tree "$t"
  [ "$t" = "$inst_tree" ] || fail "institute checkout tree '$t' is not the approved '$inst_tree'."
  [ "$(git -C "$dir/.build/checkouts/institute" rev-parse HEAD)" = "$inst_rev" ] || fail "institute checkout is not at the approved $inst_rev."
}

# route <subject-mode> <repository> <sha> <plan-result>: decides, BEFORE any
# pair authority is fetched, whether this run may use the paired planner.
# Prints "pair" only for exactly swift-institute/institute or
# swift-institute/institute-application with a well-formed trusted identity;
# prints "pin" for any other well-formed subject and for an aggregate whose plan
# did not succeed. Missing or malformed identity refuses. No caller flag forces pair.
route() {
  local mode="$1" repo="$2" sha="$3" plan_result="$4"
  case "$mode" in
    subject) ;;
    aggregate)
      case "$plan_result" in
        success) ;;
        failure|cancelled|skipped) echo pin; return 0 ;;
        *) fail "aggregate routing requires the trusted plan result; got '$plan_result'." ;;
      esac ;;
    *) fail "planner routing requires subject-mode 'subject' or 'aggregate'; got '$mode'." ;;
  esac
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || fail "subject repository '$repo' is missing or malformed."
  hex40 "$sha" || fail "subject SHA '$sha' is missing or malformed."
  case "$repo" in
    swift-institute/institute|swift-institute/institute-application) echo pair ;;
    *) echo pin ;;
  esac
}

# provenance: public-safe summary of stages, identities and digests.
provenance() {
  if [ -f "$STAGES/notes" ] && grep -qx 'mode=pin' "$STAGES/notes"; then return 0; fi
  echo "### Institute CI planner provenance"
  echo
  if [ -f "$STAGES/notes" ]; then sed 's/^/- /' "$STAGES/notes"; else echo "- notes: absent"; fi
  if [ -f "$STAGES/stages" ]; then
    echo; echo '```'; cat "$STAGES/stages"; echo '```'
    local first; first="$(awk '$3=="started"{if(!($2 in o)){n++; o[$2]=n; k[n]=$2}; s[$2]=1} $3=="ok"{delete s[$2]} END{for (i=1;i<=n;i++) if (k[i] in s) {print k[i]; exit}}' "$STAGES/stages")"
    echo; echo "First stage without completion: ${first:-none}"
    grep -q "mode=" "$STAGES/notes" 2>/dev/null || echo "Mode: unknown (pair authority could not be determined)"
  else
    echo "- stages: absent"
  fi
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0
cmd="${1:?subcommand}"; shift
case "$cmd" in
  read-pair) read_pair "$@" ;;
  route) route "$@" ;;
  verify-subject) verify_subject "$@" ;;
  verify-graph) verify_graph "$@" ;;
  stage) stage "$@" ;;
  note) note "$@" ;;
  sha256) sha256 "$@" ;;
  provenance) provenance ;;
  *) fail "unknown subcommand $cmd" ;;
esac
