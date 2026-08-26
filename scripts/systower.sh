#!/usr/bin/env bash
# ============================================================================
# Systower — Main Orchestrator
# ============================================================================
# Coordinates Docker and System update engines based on configuration.
# Called by cron or the entrypoint for immediate execution.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"
# shellcheck source=docker-update.sh
source "${SCRIPT_DIR}/docker-update.sh"
# shellcheck source=system-update.sh
source "${SCRIPT_DIR}/system-update.sh"

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    local start_time
    start_time=$(date +%s)

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  🚀 Systower run started at $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""

    if is_true "${SYSTOWER_DRY_RUN:-false}"; then
        log_warn "🔍 DRY RUN MODE — No changes will be made"
        log_info ""
    fi

    local docker_result=0
    local system_result=0

    # Run Docker updates
    if is_true "${SYSTOWER_DOCKER_ENABLED:-true}"; then
        if ! run_docker_updates; then
            docker_result=1
            log_warn "Docker updates completed with errors."
        fi
    else
        log_info "🐳 Docker updates: DISABLED"
        log_info ""
    fi

    # Run System updates
    if is_true "${SYSTOWER_SYSTEM_ENABLED:-false}"; then
        if ! run_system_updates; then
            system_result=1
            log_warn "System updates completed with errors."
        fi
    else
        log_info "🖥️  System updates: DISABLED"
        log_info ""
    fi

    # Final summary
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  ✅ Systower run completed in ${duration}s"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""

    # Return non-zero if any engine had errors
    if [ "$docker_result" -ne 0 ] || [ "$system_result" -ne 0 ]; then
        return 1
    fi
    return 0
}

# Run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    load_defaults
    main "$@"
fi
