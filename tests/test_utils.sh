#!/usr/bin/env bash
# ============================================================================
# Systower — Utils Unit Tests
# ============================================================================
# Tests for utility functions in scripts/utils.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source utils without the set -euo pipefail affecting tests
# We need to prevent utils.sh from failing on unset vars in test context
export SYSTOWER_LOG_LEVEL="error"  # Suppress log output during tests
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"

# ============================================================================
# Cron validation tests
# ============================================================================

test_validate_cron_valid() {
    validate_cron "0 4 * * *"
}

test_validate_cron_every_minute() {
    validate_cron "* * * * *"
}

test_validate_cron_complex() {
    validate_cron "*/5 2,14 1-15 * 1-5"
}

test_validate_cron_invalid_too_few_fields() {
    ! validate_cron "0 4 *"
}

test_validate_cron_invalid_too_many_fields() {
    ! validate_cron "0 4 * * * *"
}

test_validate_cron_invalid_empty() {
    ! validate_cron ""
}

# ============================================================================
# Boolean tests
# ============================================================================

test_is_boolean_true() {
    is_boolean "true"
}

test_is_boolean_false() {
    is_boolean "false"
}

test_is_boolean_TRUE() {
    is_boolean "TRUE"
}

test_is_boolean_invalid() {
    ! is_boolean "yes"
}

test_is_boolean_invalid_number() {
    ! is_boolean "1"
}

test_is_true_true() {
    is_true "true"
}

test_is_true_TRUE() {
    is_true "TRUE"
}

test_is_true_false() {
    ! is_true "false"
}

test_is_true_empty() {
    ! is_true ""
}

# ============================================================================
# Integer validation tests
# ============================================================================

test_is_positive_integer_valid() {
    is_positive_integer "30"
}

test_is_positive_integer_one() {
    is_positive_integer "1"
}

test_is_positive_integer_zero() {
    ! is_positive_integer "0"
}

test_is_positive_integer_negative() {
    ! is_positive_integer "-1"
}

test_is_positive_integer_string() {
    ! is_positive_integer "abc"
}

test_is_positive_integer_float() {
    ! is_positive_integer "3.14"
}

# ============================================================================
# CSV parsing tests
# ============================================================================

test_split_csv_simple() {
    local result
    result=$(split_csv "a,b,c")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

test_split_csv_with_spaces() {
    local result
    result=$(split_csv "a , b , c")
    local first
    first=$(echo "$result" | head -n 1)
    [ "$first" = "a" ]
}

test_split_csv_single() {
    local result
    result=$(split_csv "hello")
    [ "$result" = "hello" ]
}

test_split_csv_empty() {
    local result
    result=$(split_csv "")
    [ -z "$result" ]
}

test_in_csv_list_found() {
    in_csv_list "nginx" "postgres,nginx,redis"
}

test_in_csv_list_not_found() {
    ! in_csv_list "mysql" "postgres,nginx,redis"
}

test_in_csv_list_empty_list() {
    ! in_csv_list "nginx" ""
}

test_in_csv_list_exact_match() {
    # Should not match partial names
    ! in_csv_list "post" "postgres,nginx,redis"
}

# ============================================================================
# SSH host parsing tests
# ============================================================================

test_parse_host_full() {
    local result
    result=$(parse_host_string "admin@server.local:2222")
    [ "$result" = "admin server.local 2222" ]
}

test_parse_host_no_port() {
    local result
    result=$(parse_host_string "pi@192.168.1.100")
    [ "$result" = "pi 192.168.1.100 22" ]
}

test_parse_host_no_user() {
    local result
    result=$(parse_host_string "192.168.1.100:22")
    [ "$result" = "root 192.168.1.100 22" ]
}

test_parse_host_minimal() {
    local result
    result=$(parse_host_string "myserver.local")
    [ "$result" = "root myserver.local 22" ]
}

# ============================================================================
# Hosts file parsing tests
# ============================================================================

test_parse_hosts_file_with_comments() {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# This is a comment
pi@192.168.1.100

# Another comment
admin@server.local:2222
EOF
    local result
    result=$(parse_hosts_file "$tmpfile")
    local count
    count=$(echo "$result" | wc -l)
    rm -f "$tmpfile"
    [ "$count" -eq 2 ]
}

test_parse_hosts_file_nonexistent() {
    local result
    result=$(parse_hosts_file "/nonexistent/path")
    [ -z "$result" ]
}

# ============================================================================
# Log level tests
# ============================================================================

test_get_log_level_debug() {
    local result
    result=$(get_log_level_value "debug")
    [ "$result" -eq 0 ]
}

test_get_log_level_info() {
    local result
    result=$(get_log_level_value "info")
    [ "$result" -eq 1 ]
}

test_get_log_level_warn() {
    local result
    result=$(get_log_level_value "warn")
    [ "$result" -eq 2 ]
}

test_get_log_level_error() {
    local result
    result=$(get_log_level_value "error")
    [ "$result" -eq 3 ]
}

test_get_log_level_unknown_defaults_to_info() {
    local result
    result=$(get_log_level_value "unknown")
    [ "$result" -eq 1 ]
}

# ============================================================================
# Default loading tests
# ============================================================================

test_load_defaults_sets_cron() {
    unset SYSTOWER_CRON 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_CRON" = "0 4 * * *" ]
}

test_load_defaults_preserves_custom_value() {
    export SYSTOWER_CRON="*/5 * * * *"
    load_defaults
    [ "$SYSTOWER_CRON" = "*/5 * * * *" ]
}

test_load_defaults_docker_enabled_default() {
    unset SYSTOWER_DOCKER_ENABLED 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_DOCKER_ENABLED" = "true" ]
}

test_load_defaults_system_disabled_default() {
    unset SYSTOWER_SYSTEM_ENABLED 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_SYSTEM_ENABLED" = "false" ]
}
