#!/usr/bin/env bash
# run.sh — invoke validators against fixture repos and assert findings.
#
# Wave 1 mechanization (2026-05-10) — companion test-runner for the
# .github/scripts/validate-*.py validators.
#
# Convention:
#   fixtures/<rule-id>/pass/<scenario>/   — validator MUST emit zero findings
#                                           for <rule-id> against this fixture.
#   fixtures/<rule-id>/fail/<scenario>/   — validator MUST emit ≥1 finding
#                                           for <rule-id> against this fixture.
#   fixtures/<rule-id>/edge/<scenario>/   — validator MUST emit zero findings
#                                           against this fixture (exemption).
#
# Each scenario is a self-contained repo-shape directory with Package.swift +
# Sources/ tree.

set -eu

cd "$(dirname "$0")"
SCRIPTS_DIR="$(cd .. && pwd)"
FIXTURES_DIR="$(pwd)/fixtures"

# Map rule-id → validator script + rule prefix in TSV output. Implemented
# as a case statement so the script runs under bash 3.x (default macOS).
validator_for() {
    case "$1" in
        plat-arch-008c|plat-arch-008j|plat-arch-007)
            echo "$SCRIPTS_DIR/validate-platform-architecture.py" ;;
        api-impl-006)
            echo "$SCRIPTS_DIR/validate-file-naming.py" ;;
        pattern-001|pattern-003|pattern-004|pattern-004c|pattern-005|pattern-006)
            echo "$SCRIPTS_DIR/validate-package-shape.py" ;;
        plat-arch-008|plat-arch-008h)
            echo "$SCRIPTS_DIR/validate-layer-deps.py" ;;
        *)
            echo "" ;;
    esac
}

prefix_for() {
    case "$1" in
        plat-arch-008c)  echo "PLAT-ARCH-008c" ;;
        plat-arch-008j)  echo "PLAT-ARCH-008j" ;;
        plat-arch-007)   echo "PLAT-ARCH-007" ;;
        api-impl-006)    echo "API-IMPL-006" ;;
        pattern-001)     echo "PATTERN-001" ;;
        pattern-003)     echo "PATTERN-003" ;;
        pattern-004)     echo "PATTERN-004" ;;
        pattern-004c)    echo "PATTERN-004c" ;;
        pattern-005)     echo "PATTERN-005" ;;
        pattern-006)     echo "PATTERN-006" ;;
        plat-arch-008)   echo "PLAT-ARCH-008" ;;
        plat-arch-008h)  echo "PLAT-ARCH-008h" ;;
        *)               echo "" ;;
    esac
}

PASS_COUNT=0
FAIL_COUNT=0

run_fixture() {
    rule_id="$1"
    scenario_kind="$2"   # pass | fail | edge
    repo_root="$3"
    repo_name="$(basename "$repo_root")"

    validator="$(validator_for "$rule_id")"
    prefix="$(prefix_for "$rule_id")"
    if [ -z "$validator" ] || [ -z "$prefix" ]; then
        echo "  SKIP rule_id=$rule_id (no validator registered)"
        return 0
    fi
    if [ ! -f "$validator" ]; then
        echo "  SKIP rule_id=$rule_id (validator missing: $validator)"
        return 0
    fi

    output="$(python3 "$validator" "swift-institute-test/$repo_name" "$repo_root" 2>&1 || true)"

    finding_count="$(printf '%s\n' "$output" | grep -cE "	$prefix(	|$)" || true)"
    finding_count="${finding_count:-0}"

    case "$scenario_kind" in
        pass|edge)
            if [ "$finding_count" -eq 0 ]; then
                printf '  PASS %-25s %s/%s (zero findings)\n' "$rule_id" "$scenario_kind" "$repo_name"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                printf '  FAIL %-25s %s/%s (expected 0 findings, got %s)\n' "$rule_id" "$scenario_kind" "$repo_name" "$finding_count"
                printf '%s\n' "$output" | sed 's/^/      /'
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            ;;
        fail)
            if [ "$finding_count" -gt 0 ]; then
                printf '  PASS %-25s %s/%s (%s findings)\n' "$rule_id" "$scenario_kind" "$repo_name" "$finding_count"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                printf '  FAIL %-25s %s/%s (expected ≥1 finding, got 0)\n' "$rule_id" "$scenario_kind" "$repo_name"
                printf '%s\n' "$output" | sed 's/^/      /'
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            ;;
        *)
            echo "  SKIP unknown scenario_kind: $scenario_kind"
            ;;
    esac
}

echo "Running validator-fixture suite from $FIXTURES_DIR"
echo

for rule_dir in "$FIXTURES_DIR"/*/; do
    rule_id="$(basename "$rule_dir")"
    echo "[$rule_id]"
    for scenario_kind_dir in "$rule_dir"*/; do
        scenario_kind="$(basename "$scenario_kind_dir")"
        for repo_dir in "$scenario_kind_dir"*/; do
            [ -d "$repo_dir" ] || continue
            run_fixture "$rule_id" "$scenario_kind" "${repo_dir%/}"
        done
    done
    echo
done

echo "Total: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
