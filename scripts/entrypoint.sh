#!/usr/bin/env bash
# ============================================================================
# Systower — Container Entrypoint
# ============================================================================
# Initializes environment, validates configuration, sets up the cron
# schedule, and runs update cycles (on-start and scheduled).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# ----------------------------------------------------------------------------
# Cron setup
# ----------------------------------------------------------------------------

# Create cron job that calls systower.sh
setup_cron() {
    local cron_expr="${SYSTOWER_CRON}"
    local log_file="/var/log/systower.log"
    local env_file="/tmp/systower.env"

    # Export environment safely to an env file with secure permissions
    : > "$env_file"
    chmod 600 "$env_file" 2>/dev/null || true

    while IFS='=' read -r name value; do
        if [[ "$name" =~ ^SYSTOWER_ ]] || [ "$name" = "TZ" ] || [ "$name" = "PATH" ]; then
            printf 'export %s=%q\n' "$name" "$value" >> "$env_file"
        fi
    done < <(env)

    # Create the cron wrapper script
    cat > /tmp/systower-cron.sh << CRONEOF
#!/usr/bin/env bash
if [ -f /tmp/systower.env ]; then
    # shellcheck disable=SC1091
    source /tmp/systower.env
fi
exec ${SCRIPT_DIR}/systower.sh >> ${log_file} 2>&1
CRONEOF
    chmod +x /tmp/systower-cron.sh

    # Install cron job
    local cron_line="${cron_expr} /tmp/systower-cron.sh"
    echo "$cron_line" | crontab -

    log_info "Cron schedule set: ${cron_expr}"
    log_debug "Cron command: ${cron_line}"
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------

main() {
    # If custom command arguments are passed to the container, execute them directly
    if [ $# -gt 0 ]; then
        exec "$@"
    fi

    # Load defaults
    load_defaults

    # Print banner
    print_banner

    # Print and validate configuration
    print_config

    if ! validate_config; then
        log_error "Configuration validation failed. Please fix the errors above."
        exit 1
    fi

    # Setup cron schedule
    setup_cron

    # Run immediately on start if configured
    if is_true "${SYSTOWER_RUN_ON_START}"; then
        log_info "Running initial update cycle..."
        log_info ""
        "${SCRIPT_DIR}/systower.sh" || log_warn "Initial run completed with errors."
    else
        log_info "Skipping initial run (SYSTOWER_RUN_ON_START=false)"
    fi

    log_info "Waiting for next scheduled run (cron: ${SYSTOWER_CRON})..."
    log_info "Logs: /var/log/systower.log"
    log_info ""

    # Keep the container running by tailing the log and running crond in foreground
    touch /var/log/systower.log
    crond -f -l 8 &
    local crond_pid=$!

    # Tail log file to stdout so `docker logs` works
    tail -f /var/log/systower.log &
    local tail_pid=$!

    # Handle graceful shutdown
    trap 'log_info "Shutting down Systower..."; kill $crond_pid $tail_pid 2>/dev/null; exit 0' SIGTERM SIGINT

    # Wait for background processes
    wait $crond_pid $tail_pid
}

main "$@"
