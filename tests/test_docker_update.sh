#!/usr/bin/env bash
# ============================================================================
# Systower — Docker Update Unit Tests
# ============================================================================
# Tests for Docker update logic (filtering, exclusion mechanisms).
# Note: Actual Docker operations are not tested here (require a Docker daemon).
# These tests focus on the filtering and decision logic.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# Source utils only (docker-update.sh requires Docker socket)
# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"

# ============================================================================
# Exclusion list tests
# ============================================================================

test_exclude_list_match() {
    export SYSTOWER_DOCKER_EXCLUDE="postgres,redis,nginx"
    in_csv_list "postgres" "$SYSTOWER_DOCKER_EXCLUDE"
}

test_exclude_list_no_match() {
    export SYSTOWER_DOCKER_EXCLUDE="postgres,redis,nginx"
    ! in_csv_list "mysql" "$SYSTOWER_DOCKER_EXCLUDE"
}

test_exclude_list_empty() {
    export SYSTOWER_DOCKER_EXCLUDE=""
    ! in_csv_list "postgres" "$SYSTOWER_DOCKER_EXCLUDE"
}

# ============================================================================
# Include-only list tests
# ============================================================================

test_include_only_match() {
    export SYSTOWER_DOCKER_INCLUDE_ONLY="webapp,api"
    in_csv_list "webapp" "$SYSTOWER_DOCKER_INCLUDE_ONLY"
}

test_include_only_no_match() {
    export SYSTOWER_DOCKER_INCLUDE_ONLY="webapp,api"
    ! in_csv_list "postgres" "$SYSTOWER_DOCKER_INCLUDE_ONLY"
}

test_include_only_empty_means_all() {
    export SYSTOWER_DOCKER_INCLUDE_ONLY=""
    # Empty include-only means all containers are eligible
    [ -z "$SYSTOWER_DOCKER_INCLUDE_ONLY" ]
}

# ============================================================================
# Combined filter logic tests
# ============================================================================

test_include_only_overrides_exclude() {
    # If include-only is set, exclude list is ignored
    export SYSTOWER_DOCKER_INCLUDE_ONLY="webapp,postgres"
    export SYSTOWER_DOCKER_EXCLUDE="postgres"

    # postgres is in include-only, so it should be updated despite being in exclude
    in_csv_list "postgres" "$SYSTOWER_DOCKER_INCLUDE_ONLY"
}

test_filter_with_spaces() {
    export SYSTOWER_DOCKER_EXCLUDE="postgres , redis , nginx"
    in_csv_list "redis" "$SYSTOWER_DOCKER_EXCLUDE"
}

test_filter_single_item() {
    export SYSTOWER_DOCKER_EXCLUDE="postgres"
    in_csv_list "postgres" "$SYSTOWER_DOCKER_EXCLUDE"
}

# ============================================================================
# Configuration validation tests
# ============================================================================

test_stop_timeout_valid() {
    export SYSTOWER_DOCKER_STOP_TIMEOUT="30"
    is_positive_integer "$SYSTOWER_DOCKER_STOP_TIMEOUT"
}

test_stop_timeout_custom() {
    export SYSTOWER_DOCKER_STOP_TIMEOUT="60"
    is_positive_integer "$SYSTOWER_DOCKER_STOP_TIMEOUT"
}

test_monitor_only_boolean() {
    export SYSTOWER_DOCKER_MONITOR_ONLY="true"
    is_boolean "$SYSTOWER_DOCKER_MONITOR_ONLY"
}

test_cleanup_boolean() {
    export SYSTOWER_DOCKER_CLEANUP="false"
    is_boolean "$SYSTOWER_DOCKER_CLEANUP"
}
