#!/usr/bin/env bash
# ============================================================================
# Systower — Host System Update Engine
# ============================================================================
# Securely updates the local host machine OS packages directly via nsenter
# or chroot, enforcing official GPG/RSA signature validation on all packages.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"
# shellcheck source=notifications.sh
source "${SCRIPT_DIR}/notifications.sh"

# ----------------------------------------------------------------------------
# Host command execution
# ----------------------------------------------------------------------------

# Execute a command directly in the host OS namespace
host_exec() {
    local cmd="$1"
    if command -v nsenter >/dev/null 2>&1 && [ -d /proc/1 ]; then
        # Run via host PID 1 namespace (standard Docker host management)
        nsenter --target 1 --mount --uts --ipc --net --pid -- sh -c "$cmd"
    elif [ -d /host/etc ]; then
        # Fallback if host root is mounted at /host
        chroot /host sh -c "$cmd"
    else
        # Direct execution
        sh -c "$cmd"
    fi
}

# Detect OS of the host machine
detect_host_os() {
    local os_info=""
    if [ -f /host/etc/os-release ]; then
        os_info=$(cat /host/etc/os-release 2>/dev/null || echo "")
    else
        os_info=$(host_exec "cat /etc/os-release 2>/dev/null" 2>/dev/null || cat /etc/os-release 2>/dev/null || echo "")
    fi

    if echo "$os_info" | grep -qi "raspbian\|raspberry"; then
        echo "Raspberry Pi OS"
    elif echo "$os_info" | grep -qi "ubuntu"; then
        echo "Ubuntu"
    elif echo "$os_info" | grep -qi "debian"; then
        echo "Debian"
    elif echo "$os_info" | grep -qi "alpine"; then
        echo "Alpine"
    elif echo "$os_info" | grep -qi "arch"; then
        echo "Arch Linux"
    elif echo "$os_info" | grep -qi "fedora\|rhel\|centos\|rocky\|alma"; then
        echo "Fedora/RHEL"
    elif echo "$os_info" | grep -qi "suse\|opensuse"; then
        echo "openSUSE"
    else
        echo "Debian"
    fi
}

# Perform secure system updates on the local host machine
update_local_host() {
    local os_name
    os_name=$(detect_host_os)
    log_info "Detected Host OS: $os_name"

    local update_cmd=""
    case "$os_name" in
        "Debian"|"Ubuntu"|"Raspberry Pi OS")
            # Strict GPG verification, non-interactive upgrade, and purge obsolete packages
            update_cmd="export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get upgrade -y -qq --no-allow-insecure-repositories && apt-get autoremove -y -qq --purge && apt-get autoclean -qq"
            ;;
        "Alpine")
            # Cryptographic RSA signature verification on official APK indexes
            update_cmd="apk update && apk upgrade --no-cache"
            ;;
        "Arch Linux")
            # GPG keyring verification on Arch repositories
            update_cmd="pacman -Syu --noconfirm"
            ;;
        "Fedora/RHEL")
            # RPM-GPG signature verification on DNF/RPM packages
            update_cmd="dnf upgrade -y -q --refresh"
            ;;
        "openSUSE")
            # RPM-GPG signature verification on Zypper repositories
            update_cmd="zypper --non-interactive update --auto-agree-with-licenses"
            ;;
        *)
            update_cmd="apt-get update -qq && apt-get upgrade -y -qq --no-allow-insecure-repositories"
            ;;
    esac

    # Dry run mode
    if is_true "${SYSTOWER_DRY_RUN:-false}"; then
        log_info "  🔍 Dry run: would execute on host system: $update_cmd"
        return 0
    fi

    log_info "  Running secure system package upgrade on host machine ($os_name)..."
    local output=""
    if output=$(host_exec "$update_cmd" 2>&1); then
        log_info "  ✅ Host system update completed successfully ($os_name)!"
        log_debug "  Output: $output"
        notify_system_update "localhost (${os_name})" "success"

        # Check if reboot is needed
        local needs_reboot="no"
        needs_reboot=$(host_exec "[ -f /var/run/reboot-required ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
        if [ "$needs_reboot" = "yes" ]; then
            if is_true "${SYSTOWER_SYSTEM_REBOOT:-false}"; then
                log_warn "  🔄 Reboot required by updated kernel/packages. Rebooting host in 10s..."
                notify_system_update "localhost (${os_name})" "reboot"
                host_exec "sleep 10 && reboot" 2>/dev/null &
            else
                log_warn "  ⚠️  Reboot required on host machine (auto-reboot disabled)"
            fi
        fi
        return 0
    else
        log_error "  ❌ Host system update failed!"
        log_error "  Error: $output"
        notify_system_update "localhost (${os_name})" "error"
        return 1
    fi
}

# Run the system update process
run_system_updates() {
    log_section "🖥️  Host System Update"

    if ! is_true "${SYSTOWER_SYSTEM_ENABLED:-false}"; then
        log_info "System updates disabled (set SYSTOWER_SYSTEM_ENABLED=true to enable)."
        return 0
    fi

    local updated=0
    local failed=0

    if update_local_host; then
        updated=1
    else
        failed=1
    fi

    export _SYSTEM_UPDATED="$updated"
    export _SYSTEM_FAILED="$failed"

    [ "$failed" -eq 0 ]
}
