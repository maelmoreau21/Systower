#!/usr/bin/env bash
# ============================================================================
# Systower — Container Entrypoint
# ============================================================================
# Initializes the environment, validates configuration, sets up the cron
# schedule, and optionally runs an immediate update cycle on startup.
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

    # Export all SYSTOWER_ environment variables for the cron context
    local env_exports=""
    while IFS='=' read -r name value; do
        if [[ "$name" == SYSTOWER_* ]] || [[ "$name" == "TZ" ]] || [[ "$name" == "PATH" ]]; then
            env_exports+="export ${name}=\"${value}\"\n"
        fi
    done < <(env)

    # Create the cron wrapper script
    cat > /tmp/systower-cron.sh << CRONEOF
#!/usr/bin/env bash
$(echo -e "$env_exports")
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

    # Handle graceful shutdown
    trap 'log_info "Shutting down Systower..."; kill $crond_pid $tail_pid 2>/dev/null; exit 0' SIGTERM SIGINT

    # Tail log file to stdout so `docker logs` works
    tail -f /var/log/systower.log &
    local tail_pid=$!

    # Wait for crond to exit
    wait $crond_pid $tail_pid
}

main "$@"
