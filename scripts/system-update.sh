#!/usr/bin/env bash
# ============================================================================
# Systower — System Update Engine
# ============================================================================
# Connects to remote hosts via SSH and performs system updates using the
# appropriate package manager (apt-get for Debian/Ubuntu/Raspberry Pi OS).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# ----------------------------------------------------------------------------
# SSH execution
# ----------------------------------------------------------------------------

# Execute a command on a remote host via SSH
# Arguments: $1 - user, $2 - host, $3 - port, $4 - command
# Returns: exit code of the remote command
ssh_exec() {
    local user="$1"
    local host="$2"
    local port="$3"
    local command="$4"

    local ssh_key="${SYSTOWER_SYSTEM_SSH_KEY:-/config/ssh/id_rsa}"

    local -a ssh_opts=(
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "ConnectTimeout=10"
        -o "BatchMode=yes"
        -o "LogLevel=ERROR"
        -i "$ssh_key"
        -p "$port"
    )

    ssh "${ssh_opts[@]}" "${user}@${host}" "$command"
}

# Test SSH connectivity to a host
# Arguments: $1 - user, $2 - host, $3 - port
# Returns: 0 if reachable, 1 if not
test_ssh_connection() {
    local user="$1"
    local host="$2"
    local port="$3"

    if ssh_exec "$user" "$host" "$port" "echo ok" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ----------------------------------------------------------------------------
# System detection and update
# ----------------------------------------------------------------------------

# Detect the OS of a remote host
# Arguments: $1 - user, $2 - host, $3 - port
# Outputs: OS identifier (debian, ubuntu, raspbian, unknown)
detect_remote_os() {
    local user="$1"
    local host="$2"
    local port="$3"

    local os_info
    os_info=$(ssh_exec "$user" "$host" "$port" "cat /etc/os-release 2>/dev/null || echo 'unknown'" 2>/dev/null || echo "unknown")

    if echo "$os_info" | grep -qi "raspbian\|raspberry"; then
        echo "raspbian"
    elif echo "$os_info" | grep -qi "ubuntu"; then
        echo "ubuntu"
    elif echo "$os_info" | grep -qi "debian"; then
        echo "debian"
    elif echo "$os_info" | grep -qi "alpine"; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

# Perform system update on a remote host
# Arguments: $1 - user, $2 - host, $3 - port
# Returns: 0 on success, 1 on failure
update_remote_host() {
    local user="$1"
    local host="$2"
    local port="$3"
    local host_display="${user}@${host}:${port}"

    log_info "Connecting to $host_display..."

    # Test connectivity
    if ! test_ssh_connection "$user" "$host" "$port"; then
        log_error "Cannot connect to $host_display"
        return 1
    fi

    # Detect OS
    local os_type
    os_type=$(detect_remote_os "$user" "$host" "$port")
    log_info "  Detected OS: $os_type"

    # Build update command based on OS
    local update_cmd=""
    case "$os_type" in
        debian|ubuntu|raspbian)
            update_cmd="export DEBIAN_FRONTEND=noninteractive && "
            update_cmd+="sudo apt-get update -qq && "
            update_cmd+="sudo apt-get upgrade -y -qq --with-new-pkgs && "
            update_cmd+="sudo apt-get autoremove -y -qq && "
            update_cmd+="sudo apt-get autoclean -qq"
            ;;
        alpine)
            update_cmd="sudo apk update && sudo apk upgrade --no-cache"
            ;;
        *)
            log_warn "  Unsupported OS type: $os_type. Skipping $host_display."
            return 1
            ;;
    esac

    # Dry run mode
    if is_true "${SYSTOWER_DRY_RUN:-false}"; then
        log_info "  🔍 Dry run: would execute update on $host_display"
        log_debug "  Command: $update_cmd"
        return 0
    fi

    # Execute update
    log_info "  Running system update on $host_display..."
    local output
    if output=$(ssh_exec "$user" "$host" "$port" "$update_cmd" 2>&1); then
        log_info "  ✅ System update completed on $host_display"
        log_debug "  Output: $output"
    else
        log_error "  ❌ System update failed on $host_display"
        log_error "  Output: $output"
        return 1
    fi

    # Check if reboot is needed (Debian/Ubuntu)
    if [ "$os_type" != "alpine" ]; then
        local needs_reboot
        needs_reboot=$(ssh_exec "$user" "$host" "$port" \
            "[ -f /var/run/reboot-required ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

        if [ "$needs_reboot" = "yes" ]; then
            if is_true "${SYSTOWER_SYSTEM_REBOOT:-false}"; then
                log_warn "  🔄 Reboot required. Rebooting $host_display..."
                if ! is_true "${SYSTOWER_DRY_RUN:-false}"; then
                    ssh_exec "$user" "$host" "$port" "sudo reboot" 2>/dev/null || true
                fi
            else
                log_warn "  ⚠️  Reboot required on $host_display (auto-reboot disabled)"
            fi
        fi
    fi

    return 0
}

# ----------------------------------------------------------------------------
# Main update loop
# ----------------------------------------------------------------------------

# Collect all hosts from environment variable and hosts file
collect_hosts() {
    local hosts=()

    # Hosts from environment variable
    if [ -n "${SYSTOWER_SYSTEM_HOSTS:-}" ]; then
        while IFS= read -r host; do
            [ -n "$host" ] && hosts+=("$host")
        done < <(split_csv "$SYSTOWER_SYSTEM_HOSTS")
    fi

    # Hosts from file
    if [ -f "${SYSTOWER_SYSTEM_HOSTS_FILE:-}" ]; then
        while IFS= read -r host; do
            [ -n "$host" ] && hosts+=("$host")
        done < <(parse_hosts_file "$SYSTOWER_SYSTEM_HOSTS_FILE")
    fi

    printf '%s\n' "${hosts[@]}"
}

# Run the system update process
run_system_updates() {
    log_section "🖥️  System Updates (SSH)"

    # Check SSH key
    local ssh_key="${SYSTOWER_SYSTEM_SSH_KEY:-/config/ssh/id_rsa}"
    if [ ! -f "$ssh_key" ]; then
        log_error "SSH key not found: $ssh_key"
        log_error "Mount your SSH key: -v ~/.ssh/id_rsa:/config/ssh/id_rsa:ro"
        return 1
    fi

    # Ensure correct permissions on SSH key
    chmod 600 "$ssh_key" 2>/dev/null || true

    # Collect all hosts
    local -a all_hosts=()
    while IFS= read -r host; do
        [ -n "$host" ] && all_hosts+=("$host")
    done < <(collect_hosts)

    if [ ${#all_hosts[@]} -eq 0 ]; then
        log_warn "No hosts configured for system updates."
        log_warn "Set SYSTOWER_SYSTEM_HOSTS or mount a hosts file."
        return 0
    fi

    local total=${#all_hosts[@]}
    local updated=0
    local failed=0

    log_info "Found $total host(s) to update."
    log_info ""

    for host_string in "${all_hosts[@]}"; do
        local parsed
        parsed=$(parse_host_string "$host_string")
        local user host port
        read -r user host port <<< "$parsed"

        if update_remote_host "$user" "$host" "$port"; then
            updated=$((updated + 1))
        else
            failed=$((failed + 1))
        fi
        log_info ""
    done

    # Summary
    log_info "📊 System Update Summary:"
    log_info "  Total hosts:    $total"
    log_info "  Updated:        $updated"
    log_info "  Failed:         $failed"
    log_info ""

    [ "$failed" -eq 0 ]
}
