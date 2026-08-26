#!/usr/bin/env bash
# ============================================================================
# Systower — Health Check Post-Update
# ============================================================================
# Verifies that a container is healthy after being recreated with a new image.
# Supports Docker native healthchecks and basic running-state verification.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# ----------------------------------------------------------------------------
# Health check logic
# ----------------------------------------------------------------------------

# Check if a container has a Docker healthcheck configured
# Arguments: $1 - container name or ID
# Returns: 0 if healthcheck exists, 1 if not
has_healthcheck() {
    local container="$1"
    local hc
    hc=$(docker inspect --format='{{.Config.Healthcheck}}' "$container" 2>/dev/null || echo "")
    [ -n "$hc" ] && [ "$hc" != "<nil>" ] && [ "$hc" != "{[]  0s 0s 0s 0}" ]
}

# Get the health status of a container
# Arguments: $1 - container name or ID
# Outputs: "healthy", "unhealthy", "starting", "none", or "not_running"
get_health_status() {
    local container="$1"

    # Check if running
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    if [ "$state" != "running" ]; then
        echo "not_running"
        return
    fi

    # Check health if available
    local health
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "none")
    echo "$health"
}

# Wait for a container to become healthy
# Arguments: $1 - container name, $2 - timeout in seconds
# Returns: 0 if healthy, 1 if timeout/unhealthy
wait_for_healthy() {
    local container="$1"
    local timeout="${2:-30}"
    local interval=2
    local elapsed=0

    log_debug "Waiting for container '$container' to become healthy (timeout: ${timeout}s)..."

    while [ "$elapsed" -lt "$timeout" ]; do
        local status
        status=$(get_health_status "$container")

        case "$status" in
            healthy)
                log_info "  ✓ Container '$container' is healthy (${elapsed}s)"
                return 0
                ;;
            unhealthy)
                log_warn "  Container '$container' reported unhealthy (${elapsed}s)"
                return 1
                ;;
            not_running)
                log_error "  Container '$container' is not running"
                return 1
                ;;
            starting|none)
                # Still starting or no healthcheck — wait
                ;;
        esac

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    # Timeout reached
    local final_status
    final_status=$(get_health_status "$container")

    if [ "$final_status" = "starting" ] || [ "$final_status" = "none" ]; then
        # If no healthcheck or still starting, check if at least running
        if [ "$final_status" = "none" ]; then
            log_info "  ✓ Container '$container' is running (no healthcheck defined)"
            return 0
        fi
        log_warn "  Container '$container' still starting after ${timeout}s"
        return 1
    fi

    log_warn "  Health check timeout for '$container' after ${timeout}s (status: $final_status)"
    return 1
}

# Perform a basic health check (just verify the container is running)
# Arguments: $1 - container name, $2 - wait time in seconds
# Returns: 0 if running, 1 if not
basic_health_check() {
    local container="$1"
    local wait_time="${2:-5}"

    log_debug "Basic health check: waiting ${wait_time}s for '$container' to stabilize..."
    sleep "$wait_time"

    local state
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

    if [ "$state" = "running" ]; then
        log_info "  ✓ Container '$container' is running"
        return 0
    else
        log_error "  Container '$container' is in state: $state"
        return 1
    fi
}

# Main health check function — determines the right strategy and executes
# Arguments: $1 - container name, $2 - timeout (optional)
# Returns: 0 if healthy, 1 if not
check_container_health() {
    local container="$1"
    local timeout="${2:-${SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT:-30}}"

    log_info "  🏥 Running health check on '$container'..."

    if has_healthcheck "$container"; then
        log_debug "Container '$container' has a Docker healthcheck"
        wait_for_healthy "$container" "$timeout"
    else
        log_debug "Container '$container' has no healthcheck, using basic check"
        basic_health_check "$container" 5
    fi
}
