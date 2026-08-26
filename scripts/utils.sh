#!/usr/bin/env bash
# ============================================================================
# Systower — Utility Functions
# ============================================================================
# Shared logging, validation, and helper functions used across all scripts.
# ============================================================================

set -euo pipefail

# Guard against multiple sourcing
if [ "${_SYSTOWER_UTILS_LOADED:-}" = "true" ]; then
    return 0 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
readonly SYSTOWER_VERSION="1.0.0"
readonly SYSTOWER_NAME="Systower"

# Colors (disabled if not a terminal)
if [ -t 1 ] || [ "${SYSTOWER_FORCE_COLOR:-false}" = "true" ]; then
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    # shellcheck disable=SC2034 # COLOR_BLUE is part of the color palette, available to consumers
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_PURPLE='\033[0;35m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_GRAY='\033[0;90m'
    readonly COLOR_BOLD='\033[1m'
else
    readonly COLOR_RESET=''
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    # shellcheck disable=SC2034
    readonly COLOR_BLUE=''
    readonly COLOR_PURPLE=''
    readonly COLOR_CYAN=''
    readonly COLOR_GRAY=''
    readonly COLOR_BOLD=''
fi

# Log level numeric values
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------

# Convert log level string to numeric value
# Arguments: $1 - log level string (debug, info, warn, error)
# Returns: numeric log level via echo
get_log_level_value() {
    local level="${1,,}" # lowercase
    case "$level" in
        debug) echo "$LOG_LEVEL_DEBUG" ;;
        info)  echo "$LOG_LEVEL_INFO" ;;
        warn)  echo "$LOG_LEVEL_WARN" ;;
        error) echo "$LOG_LEVEL_ERROR" ;;
        *)     echo "$LOG_LEVEL_INFO" ;;
    esac
}

# Get the current configured log level as numeric value
get_current_log_level() {
    get_log_level_value "${SYSTOWER_LOG_LEVEL:-info}"
}

# Core logging function
# Arguments: $1 - level, $2 - color, $3 - message
_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local level_value
    level_value=$(get_log_level_value "$level")
    local current_level
    current_level=$(get_current_log_level)

    if [ "$level_value" -ge "$current_level" ]; then
        printf "${COLOR_GRAY}[%s]${COLOR_RESET} ${color}%-5s${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET} %s\n" \
            "$timestamp" "$level" "$SYSTOWER_NAME" "$message"
    fi
}

log_debug() { _log "DEBUG" "$COLOR_CYAN"   "$1"; }
log_info()  { _log "INFO"  "$COLOR_GREEN"  "$1"; }
log_warn()  { _log "WARN"  "$COLOR_YELLOW" "$1"; }
log_error() { _log "ERROR" "$COLOR_RED"    "$1"; }

# Print a section header
log_section() {
    local title="$1"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  $title"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Print Systower banner
print_banner() {
    printf "${COLOR_PURPLE}"
    printf '  ____            _                        \n'
    printf ' / ___| _   _ ___| |_ _____      _____ _ __\n'
    printf ' \\___ \\| | | / __| __/ _ \\ \\ /\\ / / _ \\ '"'"'__|\n'
    printf '  ___) | |_| \\__ \\ || (_) \\ V  V /  __/ |  \n'
    printf ' |____/ \\__, |___/\\__\\___/ \\_/\\_/ \\___|_|  \n'
    printf '        |___/                               \n'
    printf "${COLOR_RESET}\n"
    log_info "Version: ${SYSTOWER_VERSION}"
    log_info ""
}

# ----------------------------------------------------------------------------
# Validation helpers
# ----------------------------------------------------------------------------

# Check if a string is a valid cron expression (basic validation)
# Arguments: $1 - cron expression
# Returns: 0 if valid, 1 if invalid
validate_cron() {
    local cron="$1"
    local field_count
    field_count=$(echo "$cron" | awk '{print NF}')
    if [ "$field_count" -eq 5 ]; then
        return 0
    fi
    return 1
}

# Check if a value is a boolean (true/false)
# Arguments: $1 - value
# Returns: 0 if valid boolean, 1 if not
is_boolean() {
    local val="${1,,}"
    [[ "$val" == "true" || "$val" == "false" ]]
}

# Convert string to boolean (true/false → 0/1 for bash)
# Arguments: $1 - value
# Returns: 0 for true, 1 for false
is_true() {
    local val="${1,,}"
    [[ "$val" == "true" ]]
}

# Check if a value is a positive integer
# Arguments: $1 - value
# Returns: 0 if valid, 1 if not
is_positive_integer() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

# ----------------------------------------------------------------------------
# String helpers
# ----------------------------------------------------------------------------

# Split a comma-separated string into an array
# Arguments: $1 - comma-separated string
# Outputs: items one per line
split_csv() {
    local input="$1"
    if [ -z "$input" ]; then
        return
    fi
    echo "$input" | tr ',' '\n' | while read -r item; do
        # Trim whitespace
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            echo "$item"
        fi
    done
}

# Check if a value exists in a comma-separated list
# Arguments: $1 - value, $2 - comma-separated list
# Returns: 0 if found, 1 if not found
in_csv_list() {
    local value="$1"
    local csv_list="$2"

    if [ -z "$csv_list" ]; then
        return 1
    fi

    local item
    while IFS= read -r item; do
        if [ "$item" = "$value" ]; then
            return 0
        fi
    done < <(split_csv "$csv_list")

    return 1
}

# ----------------------------------------------------------------------------
# Docker helpers
# ----------------------------------------------------------------------------

# Check if Docker socket is accessible
# Returns: 0 if accessible, 1 if not
check_docker_socket() {
    if [ ! -S "/var/run/docker.sock" ]; then
        log_error "Docker socket not found at /var/run/docker.sock"
        log_error "Make sure to mount it: -v /var/run/docker.sock:/var/run/docker.sock"
        return 1
    fi
    if ! docker info > /dev/null 2>&1; then
        log_error "Cannot connect to Docker daemon. Is Docker running?"
        return 1
    fi
    return 0
}

# Get the name of a container (without leading /)
# Arguments: $1 - container ID
get_container_name() {
    docker inspect --format '{{.Name}}' "$1" 2>/dev/null | sed 's|^/||'
}

# Get the image name of a running container
# Arguments: $1 - container ID or name
get_container_image() {
    docker inspect --format '{{.Config.Image}}' "$1" 2>/dev/null
}

# Get a label value from a container
# Arguments: $1 - container ID or name, $2 - label key
get_container_label() {
    docker inspect --format "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null
}

# Check if a container has the systower exclude label
# Arguments: $1 - container ID or name
is_container_excluded_by_label() {
    local label_value
    label_value=$(get_container_label "$1" "systower.exclude")
    is_true "${label_value:-false}"
}

# Get the ID of the image currently used by a running container
# Arguments: $1 - container ID or name
get_running_image_id() {
    docker inspect --format '{{.Image}}' "$1" 2>/dev/null
}

# Get the ID of the latest pulled image
# Arguments: $1 - image name
get_latest_image_id() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null
}

# ----------------------------------------------------------------------------
# SSH helpers
# ----------------------------------------------------------------------------

# Parse a host string into user, host, and port
# Arguments: $1 - host string (user@host:port)
# Outputs: "user host port" space-separated
parse_host_string() {
    local input="$1"
    local user host port

    # Extract user
    if [[ "$input" == *"@"* ]]; then
        user="${input%%@*}"
        input="${input#*@}"
    else
        user="root"
    fi

    # Extract port
    if [[ "$input" == *":"* ]]; then
        port="${input##*:}"
        host="${input%:*}"
    else
        port="22"
        host="$input"
    fi

    echo "$user $host $port"
}

# Parse hosts from the hosts config file
# Arguments: $1 - path to hosts file
# Outputs: one host string per line (user@host:port)
parse_hosts_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        line=$(echo "$line" | xargs)
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi
        echo "$line"
    done < "$file"
}

# ----------------------------------------------------------------------------
# Environment defaults
# ----------------------------------------------------------------------------

# Load default values for all environment variables
load_defaults() {
    export SYSTOWER_CRON="${SYSTOWER_CRON:-0 4 * * *}"
    export SYSTOWER_RUN_ON_START="${SYSTOWER_RUN_ON_START:-true}"
    export SYSTOWER_DOCKER_ENABLED="${SYSTOWER_DOCKER_ENABLED:-true}"
    export SYSTOWER_SYSTEM_ENABLED="${SYSTOWER_SYSTEM_ENABLED:-false}"
    export SYSTOWER_DOCKER_EXCLUDE="${SYSTOWER_DOCKER_EXCLUDE:-}"
    export SYSTOWER_DOCKER_INCLUDE_ONLY="${SYSTOWER_DOCKER_INCLUDE_ONLY:-}"
    export SYSTOWER_DOCKER_CLEANUP="${SYSTOWER_DOCKER_CLEANUP:-true}"
    export SYSTOWER_DOCKER_STOP_TIMEOUT="${SYSTOWER_DOCKER_STOP_TIMEOUT:-30}"
    export SYSTOWER_DOCKER_MONITOR_ONLY="${SYSTOWER_DOCKER_MONITOR_ONLY:-false}"
    export SYSTOWER_SYSTEM_HOSTS="${SYSTOWER_SYSTEM_HOSTS:-}"
    export SYSTOWER_SYSTEM_HOSTS_FILE="${SYSTOWER_SYSTEM_HOSTS_FILE:-/config/hosts.conf}"
    export SYSTOWER_SYSTEM_SSH_KEY="${SYSTOWER_SYSTEM_SSH_KEY:-/config/ssh/id_rsa}"
    export SYSTOWER_SYSTEM_REBOOT="${SYSTOWER_SYSTEM_REBOOT:-false}"
    export SYSTOWER_LOG_LEVEL="${SYSTOWER_LOG_LEVEL:-info}"
    export SYSTOWER_DRY_RUN="${SYSTOWER_DRY_RUN:-false}"
}

# Print current configuration
print_config() {
    log_info "Configuration:"
    log_info "  Schedule (cron):       ${SYSTOWER_CRON}"
    log_info "  Run on start:          ${SYSTOWER_RUN_ON_START}"
    log_info "  Docker updates:        ${SYSTOWER_DOCKER_ENABLED}"
    log_info "  System updates:        ${SYSTOWER_SYSTEM_ENABLED}"
    log_info "  Log level:             ${SYSTOWER_LOG_LEVEL}"
    log_info "  Dry run:               ${SYSTOWER_DRY_RUN}"

    if is_true "$SYSTOWER_DOCKER_ENABLED"; then
        log_info "  Docker exclude:        ${SYSTOWER_DOCKER_EXCLUDE:-<none>}"
        log_info "  Docker include only:   ${SYSTOWER_DOCKER_INCLUDE_ONLY:-<all>}"
        log_info "  Docker cleanup:        ${SYSTOWER_DOCKER_CLEANUP}"
        log_info "  Docker stop timeout:   ${SYSTOWER_DOCKER_STOP_TIMEOUT}s"
        log_info "  Docker monitor only:   ${SYSTOWER_DOCKER_MONITOR_ONLY}"
    fi

    if is_true "$SYSTOWER_SYSTEM_ENABLED"; then
        log_info "  System hosts (env):    ${SYSTOWER_SYSTEM_HOSTS:-<none>}"
        log_info "  System hosts file:     ${SYSTOWER_SYSTEM_HOSTS_FILE}"
        log_info "  System SSH key:        ${SYSTOWER_SYSTEM_SSH_KEY}"
        log_info "  System reboot:         ${SYSTOWER_SYSTEM_REBOOT}"
    fi
    log_info ""
}

# Validate configuration and warn about issues
validate_config() {
    local errors=0

    if ! validate_cron "$SYSTOWER_CRON"; then
        log_error "Invalid cron expression: $SYSTOWER_CRON"
        errors=$((errors + 1))
    fi

    if ! is_boolean "$SYSTOWER_DOCKER_ENABLED"; then
        log_error "SYSTOWER_DOCKER_ENABLED must be true or false (got: $SYSTOWER_DOCKER_ENABLED)"
        errors=$((errors + 1))
    fi

    if ! is_boolean "$SYSTOWER_SYSTEM_ENABLED"; then
        log_error "SYSTOWER_SYSTEM_ENABLED must be true or false (got: $SYSTOWER_SYSTEM_ENABLED)"
        errors=$((errors + 1))
    fi

    if ! is_positive_integer "$SYSTOWER_DOCKER_STOP_TIMEOUT"; then
        log_error "SYSTOWER_DOCKER_STOP_TIMEOUT must be a positive integer (got: $SYSTOWER_DOCKER_STOP_TIMEOUT)"
        errors=$((errors + 1))
    fi

    if is_true "$SYSTOWER_SYSTEM_ENABLED"; then
        if [ -z "$SYSTOWER_SYSTEM_HOSTS" ] && [ ! -f "$SYSTOWER_SYSTEM_HOSTS_FILE" ]; then
            log_warn "System updates enabled but no hosts configured"
            log_warn "Set SYSTOWER_SYSTEM_HOSTS or mount a hosts file at ${SYSTOWER_SYSTEM_HOSTS_FILE}"
        fi
        if [ ! -f "$SYSTOWER_SYSTEM_SSH_KEY" ]; then
            log_warn "SSH key not found at ${SYSTOWER_SYSTEM_SSH_KEY}"
            log_warn "Mount your SSH key: -v ~/.ssh/id_rsa:/config/ssh/id_rsa:ro"
        fi
    fi

    if ! is_true "$SYSTOWER_DOCKER_ENABLED" && ! is_true "$SYSTOWER_SYSTEM_ENABLED"; then
        log_warn "Both Docker and System updates are disabled. Systower has nothing to do!"
    fi

    return $errors
}

# Mark as loaded to prevent double-sourcing
_SYSTOWER_UTILS_LOADED=true
