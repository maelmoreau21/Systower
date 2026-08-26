#!/usr/bin/env bash
# ============================================================================
# Systower — System Update Unit Tests
# ============================================================================
# Tests for system update logic (host parsing, OS detection patterns).
# Note: Actual SSH operations are not tested here.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"

# ============================================================================
# Host parsing tests
# ============================================================================

test_parse_host_standard() {
    local result
    result=$(parse_host_string "pi@192.168.1.100:22")
    [ "$result" = "pi 192.168.1.100 22" ]
}

test_parse_host_custom_port() {
    local result
    result=$(parse_host_string "admin@myserver.com:2222")
    [ "$result" = "admin myserver.com 2222" ]
}

test_parse_host_default_port() {
    local result
    result=$(parse_host_string "ubuntu@10.0.0.5")
    [ "$result" = "ubuntu 10.0.0.5 22" ]
}

test_parse_host_default_user_and_port() {
    local result
    result=$(parse_host_string "server.example.com")
    [ "$result" = "root server.example.com 22" ]
}

test_parse_host_ip_with_port() {
    local result
    result=$(parse_host_string "10.0.0.1:8022")
    [ "$result" = "root 10.0.0.1 8022" ]
}

# ============================================================================
# Host collection tests
# ============================================================================

test_hosts_from_env_single() {
    export SYSTOWER_SYSTEM_HOSTS="pi@192.168.1.100"
    local count
    count=$(split_csv "$SYSTOWER_SYSTEM_HOSTS" | wc -l)
    [ "$count" -eq 1 ]
}

test_hosts_from_env_multiple() {
    export SYSTOWER_SYSTEM_HOSTS="pi@192.168.1.100,admin@server.local:2222,ubuntu@10.0.0.5"
    local count
    count=$(split_csv "$SYSTOWER_SYSTEM_HOSTS" | wc -l)
    [ "$count" -eq 3 ]
}

test_hosts_from_env_empty() {
    export SYSTOWER_SYSTEM_HOSTS=""
    local result
    result=$(split_csv "$SYSTOWER_SYSTEM_HOSTS")
    [ -z "$result" ]
}

# ============================================================================
# Hosts file parsing tests
# ============================================================================

test_hosts_file_valid() {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# Raspberry Pi cluster
pi@192.168.1.100
pi@192.168.1.101:2222

# Debian server
admin@debian.local
EOF
    local count
    count=$(parse_hosts_file "$tmpfile" | wc -l)
    rm -f "$tmpfile"
    [ "$count" -eq 3 ]
}

test_hosts_file_only_comments() {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# This is just a comment
# Another comment
EOF
    local result
    result=$(parse_hosts_file "$tmpfile")
    rm -f "$tmpfile"
    [ -z "$result" ]
}

test_hosts_file_empty_lines() {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'

pi@192.168.1.100


admin@server.local

EOF
    local count
    count=$(parse_hosts_file "$tmpfile" | wc -l)
    rm -f "$tmpfile"
    [ "$count" -eq 2 ]
}

# ============================================================================
# System configuration tests
# ============================================================================

test_system_enabled_default_false() {
    unset SYSTOWER_SYSTEM_ENABLED 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_SYSTEM_ENABLED" = "false" ]
}

test_system_reboot_default_false() {
    unset SYSTOWER_SYSTEM_REBOOT 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_SYSTEM_REBOOT" = "false" ]
}

test_system_ssh_key_default() {
    unset SYSTOWER_SYSTEM_SSH_KEY 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_SYSTEM_SSH_KEY" = "/config/ssh/id_rsa" ]
}

test_system_hosts_file_default() {
    unset SYSTOWER_SYSTEM_HOSTS_FILE 2>/dev/null || true
    load_defaults
    [ "$SYSTOWER_SYSTEM_HOSTS_FILE" = "/config/hosts.conf" ]
}
