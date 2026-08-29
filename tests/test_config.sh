#!/usr/bin/env bash
# ============================================================================
# Systower — Config Unit Tests
# ============================================================================
# Tests for environment variable loading, validation, and defaults.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"

# ============================================================================
# Defaults tests
# ============================================================================

test_load_defaults_sets_expected_values() {
    unset SYSTOWER_CRON SYSTOWER_DOCKER_ENABLED SYSTOWER_RUN_ON_START 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_CRON" = "0 4 * * *" ] && \
    [ "$SYSTOWER_DOCKER_ENABLED" = "true" ] && \
    [ "$SYSTOWER_RUN_ON_START" = "true" ]
}

test_load_defaults_preserves_custom_values() {
    export SYSTOWER_CRON="0 2 * * *"
    export SYSTOWER_DOCKER_STOP_TIMEOUT="60"
    load_defaults
    [ "$SYSTOWER_CRON" = "0 2 * * *" ] && [ "$SYSTOWER_DOCKER_STOP_TIMEOUT" = "60" ]
}

test_validate_config_valid() {
    load_defaults
    validate_config
}

test_validate_config_invalid_cron() {
    load_defaults
    export SYSTOWER_CRON="invalid-cron"
    ! validate_config
}

test_validate_config_invalid_stop_timeout() {
    load_defaults
    export SYSTOWER_DOCKER_STOP_TIMEOUT="-5"
    ! validate_config
}

test_validate_config_invalid_healthcheck_timeout() {
    load_defaults
    export SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT="abc"
    ! validate_config
}

test_validate_config_invalid_log_level() {
    load_defaults
    export SYSTOWER_LOG_LEVEL="verbose_unknown"
    ! validate_config
}

test_validate_config_invalid_boolean() {
    load_defaults
    export SYSTOWER_DOCKER_CLEANUP="maybe"
    ! validate_config
}
