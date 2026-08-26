#!/usr/bin/env bash
# ============================================================================
# Systower — Notifications Unit Tests
# ============================================================================
# Tests for notification payload builders, emojis, and status colors.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"
# shellcheck source=../scripts/notifications.sh
source "${PROJECT_DIR}/scripts/notifications.sh"

# ============================================================================
# Status emoji tests
# ============================================================================

test_status_emoji_success() {
    local emoji
    emoji=$(status_emoji "success")
    [ "$emoji" = "✅" ]
}

test_status_emoji_warning() {
    local emoji
    emoji=$(status_emoji "warning")
    [ "$emoji" = "⚠️" ]
}

test_status_emoji_error() {
    local emoji
    emoji=$(status_emoji "error")
    [ "$emoji" = "❌" ]
}

test_status_emoji_rollback() {
    local emoji
    emoji=$(status_emoji "rollback")
    [ "$emoji" = "🔄" ]
}

test_status_emoji_unknown() {
    local emoji
    emoji=$(status_emoji "custom")
    [ "$emoji" = "📌" ]
}

# ============================================================================
# Status color tests
# ============================================================================

test_status_color_success() {
    local color
    color=$(status_color "success")
    [ "$color" = "3066993" ]
}

test_status_color_error() {
    local color
    color=$(status_color "error")
    [ "$color" = "15158332" ]
}

test_status_color_rollback() {
    local color
    color=$(status_color "rollback")
    [ "$color" = "10181046" ]
}

# ============================================================================
# JSON Notification builder tests
# ============================================================================

test_build_notification_json() {
    local json
    json=$(build_notification "test_event" "Test Title" "Test Message" "success")
    
    if command -v node >/dev/null 2>&1; then
        node -e "JSON.parse(process.argv[1])" "$json"
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq . >/dev/null 2>&1
    else
        echo "$json" | grep -q "test_event"
    fi
}

test_build_notification_fields() {
    local json
    json=$(build_notification "container_update" "Updated nginx" "New image pulled" "success")
    
    if command -v node >/dev/null 2>&1; then
        node -e "
            const obj = JSON.parse(process.argv[1]);
            if (obj.event !== 'container_update' || obj.title !== 'Updated nginx' || obj.status !== 'success') {
                process.exit(1);
            }
        " "$json"
    else
        echo "$json" | grep -q "container_update" && echo "$json" | grep -q "Updated nginx"
    fi
}
