#!/usr/bin/env bash
# ============================================================================
# Systower — System Update Unit Tests
# ============================================================================
# Tests for local host system update logic and OS detection.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"
# shellcheck source=../scripts/system-update.sh
source "${PROJECT_DIR}/scripts/system-update.sh"

# ============================================================================
# OS Detection tests
# ============================================================================

test_detect_host_os_debian() {
    local detected
    detected=$(detect_host_os)
    [ -n "$detected" ]
}

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
