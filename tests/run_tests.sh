#!/usr/bin/env bash
# ============================================================================
# Systower — Test Runner
# ============================================================================
# Runs all unit tests and reports results.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_NAMES=()

# Run a single test function
# Arguments: $1 - test name, $2 - test function
run_test() {
    local test_name="$1"
    local test_func="$2"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    printf "  %-50s" "$test_name"

    local output
    if output=$($test_func 2>&1); then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        printf "${GREEN}PASS${RESET}\n"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_NAMES+=("$test_name")
        printf "${RED}FAIL${RESET}\n"
        if [ -n "$output" ]; then
            printf "    ${RED}%s${RESET}\n" "$output"
        fi
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${BOLD}Test Results${RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Total:   ${BOLD}${TOTAL_TESTS}${RESET}"
    echo -e "  Passed:  ${GREEN}${PASSED_TESTS}${RESET}"
    echo -e "  Failed:  ${RED}${FAILED_TESTS}${RESET}"

    if [ ${#FAILED_NAMES[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${RED}Failed tests:${RESET}"
        for name in "${FAILED_NAMES[@]}"; do
            echo -e "    ${RED}✗ ${name}${RESET}"
        done
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${BOLD}Systower Test Suite${RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Source all test files
    local test_files=("${SCRIPT_DIR}"/test_*.sh)

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            local test_name
            test_name=$(basename "$test_file" .sh)
            echo -e "${YELLOW}▶ ${test_name}${RESET}"

            # Source the test file
            # shellcheck source=/dev/null
            source "$test_file"

            # Find and run all functions starting with "test_"
            local funcs
            funcs=$(declare -F | awk '{print $3}' | grep "^test_" || true)
            for func in $funcs; do
                run_test "$func" "$func"
            done

            # Unset test functions to avoid conflicts between files
            for func in $funcs; do
                unset -f "$func"
            done

            echo ""
        fi
    done

    print_summary

    if [ "$FAILED_TESTS" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
