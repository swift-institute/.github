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
        plat-arch-004|plat-arch-005|plat-arch-006|plat-arch-007|plat-arch-008c|plat-arch-008j|plat-arch-027)
            echo "$SCRIPTS_DIR/validate-platform-architecture.py" ;;
        api-impl-006|api-impl-007)
            echo "$SCRIPTS_DIR/validate-file-naming.py" ;;
        api-name-009)
            echo "$SCRIPTS_DIR/validate-diagnostic-format.py" ;;
        pattern-001|pattern-003|pattern-004|pattern-004b|pattern-004c|pattern-005|pattern-006|pattern-022)
            echo "$SCRIPTS_DIR/validate-package-shape.py" ;;
        plat-arch-008|plat-arch-008h)
            echo "$SCRIPTS_DIR/validate-layer-deps.py" ;;
        gh-repo-074|ci-030|ci-059)
            echo "$SCRIPTS_DIR/validate-thin-callers.py" ;;
        ci-004b)
            echo "$SCRIPTS_DIR/validate-sub-org-wrappers.py" ;;
        ci-010|ci-099)
            echo "$SCRIPTS_DIR/validate-ci-matrix.py" ;;
        ci-032)
            echo "$SCRIPTS_DIR/validate-visibility-gate.py" ;;
        ci-040|ci-042)
            echo "$SCRIPTS_DIR/validate-cache-policy.py" ;;
        ci-080)
            echo "$SCRIPTS_DIR/validate-harden-runner.py" ;;
        ci-082)
            echo "$SCRIPTS_DIR/validate-binary-install-checksum.py" ;;
        ci-021)
            echo "$SCRIPTS_DIR/validate-embedded-job.py" ;;
        ci-058)
            echo "$SCRIPTS_DIR/validate-input-defaults.py" ;;
        ci-090|ci-097)
            echo "$SCRIPTS_DIR/validate-permissions-shape.py" ;;
        ci-100)
            echo "$SCRIPTS_DIR/validate-swiftlint-rules.py" ;;
        ci-102)
            echo "$SCRIPTS_DIR/validate-composite-action-descriptions.py" ;;
        ci-103)
            echo "$SCRIPTS_DIR/validate-env-context.py" ;;
        ci-105)
            echo "$SCRIPTS_DIR/validate-continue-on-error.py" ;;
        ci-manifest-binding)
            echo "$SCRIPTS_DIR/validate-manifest-binding.py" ;;
        test-009)
            echo "$SCRIPTS_DIR/validate-file-naming.py" ;;
        *)
            echo "" ;;
    esac
}

prefix_for() {
    case "$1" in
        plat-arch-004)   echo "PLAT-ARCH-004" ;;
        plat-arch-005)   echo "PLAT-ARCH-005" ;;
        plat-arch-006)   echo "PLAT-ARCH-006" ;;
        plat-arch-008c)  echo "PLAT-ARCH-008c" ;;
        plat-arch-008j)  echo "PLAT-ARCH-008j" ;;
        plat-arch-007)   echo "PLAT-ARCH-007" ;;
        plat-arch-027)   echo "PLAT-ARCH-027" ;;
        api-impl-006)    echo "API-IMPL-006" ;;
        api-impl-007)    echo "API-IMPL-007" ;;
        api-name-009)    echo "API-NAME-009" ;;
        pattern-001)     echo "PATTERN-001" ;;
        pattern-003)     echo "PATTERN-003" ;;
        pattern-004)     echo "PATTERN-004" ;;
        pattern-004b)    echo "PATTERN-004b" ;;
        pattern-004c)    echo "PATTERN-004c" ;;
        pattern-022)     echo "PATTERN-022" ;;
        pattern-005)     echo "PATTERN-005" ;;
        pattern-006)     echo "PATTERN-006" ;;
        plat-arch-008)   echo "PLAT-ARCH-008" ;;
        plat-arch-008h)  echo "PLAT-ARCH-008h" ;;
        gh-repo-074)     echo "GH-REPO-074" ;;
        ci-004b)         echo "CI-004b" ;;
        ci-010)          echo "CI-010" ;;
        ci-030)          echo "CI-030" ;;
        ci-099)          echo "CI-099" ;;
        ci-021)          echo "CI-021" ;;
        ci-058)          echo "CI-058" ;;
        ci-090)          echo "CI-090" ;;
        ci-097)          echo "CI-097" ;;
        ci-100)          echo "CI-100" ;;
        ci-102)          echo "CI-102" ;;
        ci-032)          echo "CI-032" ;;
        ci-040)          echo "CI-040" ;;
        ci-042)          echo "CI-042" ;;
        ci-059)          echo "CI-059" ;;
        ci-080)          echo "CI-080" ;;
        ci-082)          echo "CI-082" ;;
        ci-103)          echo "CI-103" ;;
        ci-105)          echo "CI-105" ;;
        ci-manifest-binding) echo "CI-MANIFEST-BINDING" ;;
        test-009)        echo "TEST-009" ;;
        *)               echo "" ;;
    esac
}

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

run_fixture() {
    rule_id="$1"
    scenario_kind="$2"   # pass | fail | edge
    repo_root="$3"
    repo_name="$(basename "$repo_root")"

    validator="$(validator_for "$rule_id")"
    prefix="$(prefix_for "$rule_id")"
    if [ -z "$validator" ] || [ -z "$prefix" ]; then
        echo "  SKIP rule_id=$rule_id (no validator registered)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return 0
    fi
    if [ ! -f "$validator" ]; then
        echo "  SKIP rule_id=$rule_id (validator missing: $validator)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
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
            SKIP_COUNT=$((SKIP_COUNT + 1))
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

echo "Total: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
if [ "$FAIL_COUNT" -gt 0 ] || [ "$SKIP_COUNT" -gt 0 ]; then
    if [ "$SKIP_COUNT" -gt 0 ]; then
        echo "FAIL: $SKIP_COUNT silent SKIP(s) — every fixture dir MUST resolve to a registered validator." >&2
    fi
    exit 1
fi
