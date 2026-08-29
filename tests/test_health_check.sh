#!/usr/bin/env bash
# ============================================================================
# Systower — Health Check Unit Tests
# ============================================================================
# Tests for health check helper logic and functions.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"
# shellcheck source=../scripts/health-check.sh
source "${PROJECT_DIR}/scripts/health-check.sh"

test_healthcheck_script_loads() {
    # Verify functions are defined
    type has_healthcheck >/dev/null 2>&1
    type get_health_status >/dev/null 2>&1
    type wait_for_healthy >/dev/null 2>&1
    type basic_health_check >/dev/null 2>&1
    type check_container_health >/dev/null 2>&1
}

test_healthcheck_timeout_default() {
    load_defaults
    [ "${SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT}" = "30" ]
}

test_healthcheck_timeout_custom() {
    export SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT="45"
    load_defaults
    [ "${SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT}" = "45" ]
}
