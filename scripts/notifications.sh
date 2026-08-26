#!/usr/bin/env bash
# ============================================================================
# Systower — Notification System
# ============================================================================
# Sends notifications to Discord, Slack, Telegram, and generic webhooks
# when updates are performed, fail, or require attention.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# ----------------------------------------------------------------------------
# Notification formatting
# ----------------------------------------------------------------------------

# Build a notification message
# Arguments: $1 - event type, $2 - title, $3 - message, $4 - status (success|warning|error)
build_notification() {
    local event_type="$1"
    local title="$2"
    local message="$3"
    local status="${4:-info}"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    echo "{\"event\":\"${event_type}\",\"title\":\"${title}\",\"message\":\"${message}\",\"status\":\"${status}\",\"timestamp\":\"${timestamp}\",\"hostname\":\"$(hostname)\"}"
}

# Get emoji for status
status_emoji() {
    case "$1" in
        success) echo "✅" ;;
        warning) echo "⚠️" ;;
        error)   echo "❌" ;;
        info)    echo "ℹ️" ;;
        rollback) echo "🔄" ;;
        *)       echo "📌" ;;
    esac
}

# Get color code for Discord/Slack
status_color() {
    case "$1" in
        success)  echo "3066993" ;;  # Green
        warning)  echo "16776960" ;; # Yellow
        error)    echo "15158332" ;; # Red
        info)     echo "3447003" ;;  # Blue
        rollback) echo "10181046" ;; # Purple
        *)        echo "9807270" ;;  # Gray
    esac
}

# ----------------------------------------------------------------------------
# Discord
# ----------------------------------------------------------------------------

send_discord() {
    local webhook_url="$1"
    local title="$2"
    local message="$3"
    local status="$4"
    local emoji
    emoji=$(status_emoji "$status")
    local color
    color=$(status_color "$status")

    local payload
    payload=$(cat <<EOF
{
    "embeds": [{
        "title": "${emoji} ${title}",
        "description": "${message}",
        "color": ${color},
        "footer": {"text": "Systower v${SYSTOWER_VERSION}"},
        "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    }]
}
EOF
)

    if curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" | grep -q "^2"; then
        log_debug "Discord notification sent"
    else
        log_warn "Failed to send Discord notification"
    fi
}

# ----------------------------------------------------------------------------
# Slack
# ----------------------------------------------------------------------------

send_slack() {
    local webhook_url="$1"
    local title="$2"
    local message="$3"
    local status="$4"
    local emoji
    emoji=$(status_emoji "$status")

    local payload
    payload=$(cat <<EOF
{
    "blocks": [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": "${emoji} ${title}"}
        },
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": "${message}"}
        },
        {
            "type": "context",
            "elements": [{"type": "mrkdwn", "text": "Systower v${SYSTOWER_VERSION} • $(date '+%Y-%m-%d %H:%M:%S')"}]
        }
    ]
}
EOF
)

    if curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" | grep -q "^2"; then
        log_debug "Slack notification sent"
    else
        log_warn "Failed to send Slack notification"
    fi
}

# ----------------------------------------------------------------------------
# Telegram
# ----------------------------------------------------------------------------

send_telegram() {
    local bot_token="$1"
    local chat_id="$2"
    local title="$3"
    local message="$4"
    local status="$5"
    local emoji
    emoji=$(status_emoji "$status")

    local text
    text="${emoji} *${title}*\n\n${message}\n\n_Systower v${SYSTOWER_VERSION} • $(date '+%Y-%m-%d %H:%M:%S')_"

    if curl -s -o /dev/null -w "%{http_code}" \
        -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" | grep -q "^2"; then
        log_debug "Telegram notification sent"
    else
        log_warn "Failed to send Telegram notification"
    fi
}

# ----------------------------------------------------------------------------
# Generic Webhook
# ----------------------------------------------------------------------------

send_webhook() {
    local url="$1"
    local title="$2"
    local message="$3"
    local status="$4"

    local payload
    payload=$(build_notification "update" "$title" "$message" "$status")

    if curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url" | grep -q "^2"; then
        log_debug "Webhook notification sent"
    else
        log_warn "Failed to send webhook notification"
    fi
}

# ----------------------------------------------------------------------------
# Main notification dispatcher
# ----------------------------------------------------------------------------

# Send notification to all configured channels
# Arguments: $1 - title, $2 - message, $3 - status (success|warning|error|info|rollback)
notify() {
    local title="$1"
    local message="$2"
    local status="${3:-info}"

    # Check if notifications are enabled
    if ! is_true "${SYSTOWER_NOTIFY_ENABLED:-false}"; then
        return 0
    fi

    log_debug "Sending notifications: $title ($status)"

    # Read config from JSON file if available
    local config_file="${SYSTOWER_CONFIG_FILE:-/config/systower.json}"

    # Discord
    local discord_url="${SYSTOWER_NOTIFY_DISCORD:-}"
    if [ -z "$discord_url" ] && [ -f "$config_file" ]; then
        discord_url=$(jq -r '.notifications.discord.webhookUrl // empty' "$config_file" 2>/dev/null || echo "")
    fi
    if [ -n "$discord_url" ]; then
        send_discord "$discord_url" "$title" "$message" "$status" &
    fi

    # Slack
    local slack_url="${SYSTOWER_NOTIFY_SLACK:-}"
    if [ -z "$slack_url" ] && [ -f "$config_file" ]; then
        slack_url=$(jq -r '.notifications.slack.webhookUrl // empty' "$config_file" 2>/dev/null || echo "")
    fi
    if [ -n "$slack_url" ]; then
        send_slack "$slack_url" "$title" "$message" "$status" &
    fi

    # Telegram
    local tg_token="${SYSTOWER_NOTIFY_TELEGRAM_TOKEN:-}"
    local tg_chat="${SYSTOWER_NOTIFY_TELEGRAM_CHAT:-}"
    if [ -z "$tg_token" ] && [ -f "$config_file" ]; then
        tg_token=$(jq -r '.notifications.telegram.botToken // empty' "$config_file" 2>/dev/null || echo "")
        tg_chat=$(jq -r '.notifications.telegram.chatId // empty' "$config_file" 2>/dev/null || echo "")
    fi
    if [ -n "$tg_token" ] && [ -n "$tg_chat" ]; then
        send_telegram "$tg_token" "$tg_chat" "$title" "$message" "$status" &
    fi

    # Generic webhook
    local webhook_url="${SYSTOWER_NOTIFY_WEBHOOK:-}"
    if [ -z "$webhook_url" ] && [ -f "$config_file" ]; then
        webhook_url=$(jq -r '.notifications.webhook.url // empty' "$config_file" 2>/dev/null || echo "")
    fi
    if [ -n "$webhook_url" ]; then
        send_webhook "$webhook_url" "$title" "$message" "$status" &
    fi

    # Wait for all background notification jobs
    wait
}

# Convenience functions for common events
notify_update_success() {
    local container="$1"
    local old_image="${2:-}"
    local new_image="${3:-}"
    local msg="Container *${container}* has been updated successfully."
    if [ -n "$old_image" ] && [ -n "$new_image" ] && [ "$old_image" != "unknown" ]; then
        msg="Container *${container}* updated from \`${old_image}\` to \`${new_image}\`."
    fi
    notify "Container Updated" "$msg" "success"
}

notify_update_failed() {
    local container="$1"
    local reason="${2:-Unknown error}"
    notify "Update Failed" "Failed to update container *${container}*: ${reason}" "error"
}

notify_rollback() {
    local container="$1"
    local reason="${2:-Health check failed}"
    notify "Rollback Performed" "Container *${container}* was rolled back: ${reason}" "rollback"
}

notify_system_update() {
    local host="$1"
    local status="$2"
    if [ "$status" = "success" ]; then
        notify "System Updated" "System *${host}* has been updated successfully." "success"
    else
        notify "System Update Failed" "Failed to update system *${host}*." "error"
    fi
}

notify_run_summary() {
    local docker_updated="${1:-0}"
    local docker_failed="${2:-0}"
    local system_updated="${3:-0}"
    local system_failed="${4:-0}"
    local duration="${5:-0}"

    local msg="Run completed in ${duration}s.\n"
    msg+="Docker: ${docker_updated} updated, ${docker_failed} failed\n"
    msg+="System: ${system_updated} updated, ${system_failed} failed"

    local status="success"
    if [ "$docker_failed" -gt 0 ] || [ "$system_failed" -gt 0 ]; then
        status="warning"
    fi

    notify "Systower Run Complete" "$msg" "$status"
}
