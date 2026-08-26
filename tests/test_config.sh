#!/usr/bin/env bash
# ============================================================================
# Systower — Config Unit Tests
# ============================================================================
# Tests for config JSON initialization, reading, and overrides.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

export SYSTOWER_LOG_LEVEL="error"
export SYSTOWER_FORCE_COLOR="false"

# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"

# Helper to check valid JSON with jq or node
verify_json() {
    local file_or_string="$1"
    if [ -f "$file_or_string" ]; then
        if command -v node >/dev/null 2>&1; then
            node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$file_or_string" >/dev/null 2>&1
        elif command -v jq >/dev/null 2>&1; then
            jq . "$file_or_string" >/dev/null 2>&1
        else
            grep -q "{" "$file_or_string"
        fi
    else
        if command -v node >/dev/null 2>&1; then
            node -e "JSON.parse(process.argv[1])" "$file_or_string" >/dev/null 2>&1
        elif command -v jq >/dev/null 2>&1; then
            echo "$file_or_string" | jq . >/dev/null 2>&1
        else
            echo "$file_or_string" | grep -q "{"
        fi
    fi
}

# ============================================================================
# Config file tests
# ============================================================================

test_init_config_file_creates_valid_json() {
    local tmpfile="${PROJECT_DIR}/tests/.tmp_test_config.json"
    rm -f "$tmpfile"
    export SYSTOWER_CONFIG_FILE="$tmpfile"

    init_config_file

    local res=0
    if [ -f "$tmpfile" ]; then
        verify_json "$tmpfile" || res=1
    else
        res=1
    fi
    rm -f "$tmpfile"
    return $res
}

test_read_config_from_file() {
    local tmpfile="${PROJECT_DIR}/tests/.tmp_read_config.json"
    cat > "$tmpfile" << 'EOF'
{
    "general": {
        "cron": "*/15 * * * *",
        "logLevel": "debug"
    },
    "docker": {
        "stopTimeout": 45
    }
}
EOF
    export SYSTOWER_CONFIG_FILE="$tmpfile"

    local cron_val
    cron_val=$(read_config '.general.cron' 'fallback')
    local timeout_val
    timeout_val=$(read_config '.docker.stopTimeout' '30')

    rm -f "$tmpfile"

    [ "$cron_val" = "*/15 * * * *" ] && [ "$timeout_val" = "45" ]
}

test_read_config_fallback_when_missing() {
    export SYSTOWER_CONFIG_FILE="/nonexistent/systower.json"
    local val
    val=$(read_config '.general.missingKey' 'my-fallback')
    [ "$val" = "my-fallback" ]
}

test_validate_config_oidc_check() {
    load_defaults
    export SYSTOWER_OIDC_ENABLED="true"
    export SYSTOWER_OIDC_ISSUER=""
    export SYSTOWER_OIDC_CLIENT_ID=""

    # Should fail validation because issuer and client_id are missing
    ! validate_config
}
