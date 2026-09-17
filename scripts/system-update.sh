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
    local kernel_info=""
    if [ -f /host/etc/os-release ]; then
        os_info=$(cat /host/etc/os-release 2>/dev/null || echo "")
    else
        os_info=$(host_exec "cat /etc/os-release 2>/dev/null" 2>/dev/null || cat /etc/os-release 2>/dev/null || echo "")
    fi
    kernel_info=$(host_exec "uname -r 2>/dev/null; cat /proc/version 2>/dev/null" 2>/dev/null || cat /proc/version 2>/dev/null || echo "")

    # Check for Docker Desktop or WSL environments
    if echo "$os_info" | grep -qi "docker desktop" || echo "$kernel_info" | grep -qi "microsoft\|wsl"; then
        echo "Docker Desktop / WSL"
        return 0
    fi

    if echo "$os_info" | grep -qi "raspbian\|raspberry\|rpi"; then
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
        echo "Unknown"
    fi
}

# Immunize host network managers (dhcpcd, NetworkManager) against Docker virtual interfaces
# to permanently prevent the host from dropping the default gateway route.
immunize_host_network() {
    if ! is_true "${SYSTOWER_RPI_NETWORK_IMMUNITY:-true}"; then
        return 0
    fi

    # 1. dhcpcd (standard on Raspberry Pi OS Buster / Bullseye)
    local has_dhcpcd=""
    has_dhcpcd=$(host_exec "[ -f /etc/dhcpcd.conf ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    if [ "$has_dhcpcd" = "yes" ]; then
        local has_deny=""
        has_deny=$(host_exec "grep -E '^[[:space:]]*denyinterfaces.*veth' /etc/dhcpcd.conf 2>/dev/null || echo ''" 2>/dev/null || echo "")
        if [ -z "$has_deny" ]; then
            log_warn "  🛡️ Raspberry Pi / Debian network protection: adding 'denyinterfaces veth* docker* br-*' to /etc/dhcpcd.conf..."
            host_exec "printf '\n# Systower: Prevent Docker veth interfaces from dropping default route\ndenyinterfaces veth* docker* br-*\n' >> /etc/dhcpcd.conf && (systemctl reload dhcpcd 2>/dev/null || systemctl restart dhcpcd 2>/dev/null || true)" 2>/dev/null || true
            log_info "  ✅ /etc/dhcpcd.conf successfully immunized against Docker veth route drops!"
        else
            log_debug "  ✓ /etc/dhcpcd.conf already has denyinterfaces rule."
        fi
    fi

    # 2. NetworkManager (standard on Raspberry Pi OS Bookworm / Debian 12 / Ubuntu)
    local has_nm=""
    has_nm=$(host_exec "[ -d /etc/NetworkManager ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    if [ "$has_nm" = "yes" ]; then
        local has_nm_conf=""
        has_nm_conf=$(host_exec "[ -f /etc/NetworkManager/conf.d/docker-veth.conf ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
        if [ "$has_nm_conf" = "no" ]; then
            log_warn "  🛡️ NetworkManager protection: configuring unmanaged devices for Docker (veth, docker0, br)..."
            host_exec "mkdir -p /etc/NetworkManager/conf.d && printf '[keyfile]\nunmanaged-devices=interface-name:veth*;interface-name:br-*;interface-name:docker0\n' > /etc/NetworkManager/conf.d/docker-veth.conf && (systemctl reload NetworkManager 2>/dev/null || true)" 2>/dev/null || true
            log_info "  ✅ NetworkManager successfully immunized against Docker veth route drops!"
        else
            log_debug "  ✓ NetworkManager already configured to ignore Docker interfaces."
        fi
    fi

    return 0
}

# Perform secure system updates on the local host machine
update_local_host() {
    local os_name
    os_name=$(detect_host_os)
    log_info "Detected Host OS: $os_name"

    # Refuse host OS updates in virtualized/containerized desktop environments
    if [ "$os_name" = "Docker Desktop / WSL" ]; then
        log_warn "  ⚠️ Host OS package updates are not supported on Docker Desktop / WSL environments."
        log_warn "  Docker Desktop manages its own engine updates via the host application."
        return 0
    fi

    if [ "$os_name" = "Unknown" ]; then
        log_warn "  ⚠️ Unrecognized host OS. Skipping system updates to prevent package manager conflicts."
        return 0
    fi

    # Immunize host networking prior to package operations
    immunize_host_network

    local update_cmd=""
    case "$os_name" in
        "Raspberry Pi OS"|"Debian"|"Ubuntu")
            # 1. Hold Docker & Containerd & D-Bus packages to NEVER let package upgrades terminate dockerd mid-run
            # 2. Place policy-rc.d returning 101 so invoke-rc.d will not restart daemons unexpectedly
            # 3. Use safe apt upgrade instead of dist-upgrade to preserve core networking/init dependencies
            # 4. Remove policy-rc.d on exit/trap and ensure network services remain running
            update_cmd='export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 && \
apt-mark hold docker-ce docker-ce-cli containerd.io docker.io containerd runc docker-buildx-plugin docker-compose-plugin dbus dbus-bin dbus-daemon dbus-system-bus-common 2>/dev/null || true && \
printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d && \
trap "rm -f /usr/sbin/policy-rc.d" EXIT INT TERM && \
dpkg --configure -a --force-confold 2>/dev/null || true && \
apt-get install -f -y -qq && \
apt-get update -qq && \
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && \
if command -v rpi-eeprom-update >/dev/null 2>&1; then rpi-eeprom-update -a 2>/dev/null || true; fi && \
apt-get autoremove -y -qq --purge && \
apt-get autoclean -qq && \
rm -f /usr/sbin/policy-rc.d && \
(systemctl is-active dhcpcd >/dev/null 2>&1 || systemctl restart dhcpcd 2>/dev/null || true) && \
(systemctl is-active NetworkManager >/dev/null 2>&1 || systemctl restart NetworkManager 2>/dev/null || true)'
            ;;
        "Alpine")
            # Cryptographic RSA signature verification on official APK indexes
            update_cmd="apk update && apk upgrade --no-cache"
            ;;
        "Arch Linux")
            # GPG keyring verification on Arch repositories, safely excluding Docker daemon packages
            update_cmd="pacman -Syu --noconfirm --ignore docker,containerd,runc,dbus"
            ;;
        "Fedora/RHEL")
            # RPM-GPG signature verification on DNF/RPM packages, safely excluding Docker daemon packages
            update_cmd="dnf upgrade -y -q --refresh --exclude='docker*,containerd*,runc*,dbus*'"
            ;;
        "openSUSE")
            # RPM-GPG signature verification on Zypper repositories, safely excluding Docker daemon packages
            update_cmd="zypper --non-interactive update --auto-agree-with-licenses --exclude='docker,containerd,runc,dbus'"
            ;;
        *)
            log_warn "Unsupported distribution '$os_name'. Skipping host updates."
            return 0
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

        # Verify host default gateway route post-update
        local has_default_route=""
        has_default_route=$(host_exec "ip route show default 2>/dev/null || echo ''" 2>/dev/null || echo "")
        if [ -z "$has_default_route" ]; then
            log_warn "  ⚠️ Default network route was not detected post-update. Attempting to refresh DHCP/NetworkManager..."
            host_exec "systemctl restart dhcpcd 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || true" 2>/dev/null || true
        fi

        # Check if reboot is needed
        local needs_reboot="no"
        needs_reboot=$(host_exec "[ -f /var/run/reboot-required ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
        if [ "$needs_reboot" = "yes" ]; then
            if is_true "${SYSTOWER_SYSTEM_REBOOT:-false}"; then
                log_warn "  🚨 REBOOT TRIGGERED: The host machine will reboot in 10 seconds to apply kernel/system updates (SYSTOWER_SYSTEM_REBOOT=true)."
                notify_system_update "localhost (${os_name})" "reboot"
                host_exec "sleep 10 && reboot" 2>/dev/null &
            else
                log_warn "  ⚠️  Reboot required on host machine to apply updates (auto-reboot disabled, SYSTOWER_SYSTEM_REBOOT=false)."
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

# Verify if host namespace is accessible
check_host_access() {
    if ! command -v nsenter >/dev/null 2>&1 && [ ! -d /host/etc ]; then
        log_error "nsenter utility not found and /host not mounted."
        return 1
    fi

    local test_out=""
    if ! test_out=$(host_exec "true" 2>&1); then
        log_error "Cannot execute commands in host namespace."
        log_error "To enable host updates, please ensure 'pid: \"host\"' and 'privileged: true' are enabled in your docker-compose.yml"
        log_debug "Host exec error: $test_out"
        return 1
    fi
    return 0
}

# Run the system update process
run_system_updates() {
    log_section "🖥️  Host System Update"

    if ! is_true "${SYSTOWER_SYSTEM_ENABLED:-false}"; then
        log_info "System updates disabled (set SYSTOWER_SYSTEM_ENABLED=true to enable)."
        return 0
    fi

    if ! check_host_access; then
        export _SYSTEM_UPDATED=0
        export _SYSTEM_FAILED=1
        notify_system_update "localhost" "error"
        return 1
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
