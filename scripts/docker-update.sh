#!/usr/bin/env bash
# ============================================================================
# Systower — Docker Container Update Engine
# ============================================================================
# Ultra-lightweight, robust container updater that inspects running containers,
# pulls the latest images, recreates containers with all original settings
# (networks, mounts, env, labels, restart policy), and provides foolproof
# instant rollback on startup failure.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"
# shellcheck source=notifications.sh
source "${SCRIPT_DIR}/notifications.sh"
# shellcheck source=health-check.sh
source "${SCRIPT_DIR}/health-check.sh"

# ----------------------------------------------------------------------------
# Container filtering
# ----------------------------------------------------------------------------

# Determine if a container should be updated
# Arguments: $1 - container ID
# Returns: 0 if should update, 1 if should skip
should_update_container() {
    local container_id="$1"
    local container_name
    container_name=$(get_container_name "$container_id")
    local image_name
    image_name=$(get_container_image "$container_id")

    # Never update Systower itself
    # 1. Match by container name
    if [ "$container_name" = "systower" ] || [ "$container_name" = "${SYSTOWER_CONTAINER_NAME:-systower}" ]; then
        log_debug "Skipping self (Systower container name match)"
        return 1
    fi

    # 2. Match by cgroups (v1 / v2 / systemd / cgroupfs)
    local self_cgroup_id
    self_cgroup_id=$(cat /proc/self/cgroup /proc/1/cpuset 2>/dev/null | grep -o '[0-9a-f]\{64\}' | head -n 1 || echo "")
    if [ -n "$self_cgroup_id" ] && [ "$container_id" = "$self_cgroup_id" ]; then
        log_debug "Skipping self (Systower cgroup ID match)"
        return 1
    fi

    # 3. Match by container hostname (short ID)
    local host_name
    host_name=$(hostname 2>/dev/null || echo "")
    if [ -n "$host_name" ] && [[ "$container_id" == "$host_name"* ]]; then
        log_debug "Skipping self (Systower hostname match)"
        return 1
    fi

    # 4. Match by image name
    if [[ "$image_name" == *"systower"* ]] && [ "${SYSTOWER_UPDATE_SELF:-false}" != "true" ]; then
        log_debug "Skipping self (Systower image match: $image_name)"
        return 1
    fi

    # Skip systower backup containers if any remain
    if [[ "$container_name" == *_systower_bak ]]; then
        return 1
    fi

    # Check label exclusion: systower.exclude=true
    if is_container_excluded_by_label "$container_id"; then
        log_debug "Skipping '$container_name' (excluded by label)"
        return 1
    fi

    # Check include-only list (takes priority over exclude list)
    if [ -n "${SYSTOWER_DOCKER_INCLUDE_ONLY:-}" ]; then
        if ! in_csv_list "$container_name" "$SYSTOWER_DOCKER_INCLUDE_ONLY"; then
            log_debug "Skipping '$container_name' (not in include-only list)"
            return 1
        fi
        return 0
    fi

    # Check exclude list
    if [ -n "${SYSTOWER_DOCKER_EXCLUDE:-}" ]; then
        if in_csv_list "$container_name" "$SYSTOWER_DOCKER_EXCLUDE"; then
            log_debug "Skipping '$container_name' (in exclude list)"
            return 1
        fi
    fi

    return 0
}

# ----------------------------------------------------------------------------
# Container recreation with safe rollback
# ----------------------------------------------------------------------------

# Recreate a container with the latest image while preserving full config
# Arguments: $1 - container ID
# Returns: 0 on success, 1 on failure
recreate_container() {
    local container_id="$1"
    local container_name
    container_name=$(get_container_name "$container_id")
    local image_name
    image_name=$(get_container_image "$container_id")

    log_info "Recreating container '$container_name' with new image..."

    # Extract full container configuration using docker inspect
    local inspect_json
    inspect_json=$(docker inspect "$container_id")

    # Network mode (primary network)
    local network_mode
    network_mode=$(echo "$inspect_json" | jq -r '.[0].HostConfig.NetworkMode' 2>/dev/null || echo "default")

    # Extract extra network settings
    local extra_networks
    extra_networks=$(echo "$inspect_json" | jq -r '.[0].NetworkSettings.Networks | keys[]' 2>/dev/null | grep -v '^bridge$' | grep -v '^host$' | grep -v '^none$' || echo "")

    # Build the docker run command arguments
    local -a run_args=()

    # Container name
    run_args+=("--name" "$container_name")

    # Restart policy
    local restart_policy
    restart_policy=$(echo "$inspect_json" | jq -r '.[0].HostConfig.RestartPolicy.Name' 2>/dev/null || echo "")
    local restart_max
    restart_max=$(echo "$inspect_json" | jq -r '.[0].HostConfig.RestartPolicy.MaximumRetryCount' 2>/dev/null || echo "0")
    if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ] && [ "$restart_policy" != "null" ]; then
        if [ "$restart_policy" = "on-failure" ] && [ "$restart_max" -gt 0 ]; then
            run_args+=("--restart" "${restart_policy}:${restart_max}")
        else
            run_args+=("--restart" "$restart_policy")
        fi
    fi

    # Environment variables (null-delimited for safe multiline values)
    while IFS= read -r -d '' env_var; do
        [ -n "$env_var" ] && run_args+=("-e" "$env_var")
    done < <(echo "$inspect_json" | jq -j '.[0].Config.Env[]? // empty | . + "\u0000"' 2>/dev/null || true)

    # Network mode
    if [ "$network_mode" != "default" ] && [ "$network_mode" != "bridge" ]; then
        run_args+=("--network" "$network_mode")
    fi

    # Port bindings (with IPv6 bracket support)
    if [ "$network_mode" != "host" ] && [[ "$network_mode" != container:* ]]; then
        local port_bindings
        port_bindings=$(echo "$inspect_json" | jq -r '
            .[0].HostConfig.PortBindings // {} | to_entries[] |
            .key as $container_port |
            .value[]? |
            (if .HostIp != "" and .HostIp != "0.0.0.0" then
                (if (.HostIp | contains(":")) then "[" + .HostIp + "]:" else .HostIp + ":" end)
             else "" end) +
            (if .HostPort != "" then .HostPort + ":" else "" end) +
            $container_port
        ' 2>/dev/null || echo "")
        while IFS= read -r binding; do
            [ -n "$binding" ] && run_args+=("-p" "$binding")
        done <<< "$port_bindings"
    fi

    # Volume mounts (binds)
    local binds
    binds=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Binds[]?' 2>/dev/null || echo "")
    while IFS= read -r bind; do
        [ -n "$bind" ] && run_args+=("-v" "$bind")
    done <<< "$binds"

    # Named volume mounts not already present in binds
    local volume_mounts
    volume_mounts=$(echo "$inspect_json" | jq -r '
        .[0].Mounts[]? | select(.Type == "volume" and .Name != null and .Name != "") |
        .Name + ":" + .Destination + (if .RW == false then ":ro" else "" end)
    ' 2>/dev/null || echo "")
    while IFS= read -r mount; do
        if [ -n "$mount" ]; then
            if ! printf '%s\n' "$binds" | grep -Fxq "$mount"; then
                run_args+=("-v" "$mount")
            fi
        fi
    done <<< "$volume_mounts"

    # Labels (null-delimited for safe multiline strings)
    while IFS= read -r -d '' label; do
        [ -n "$label" ] && run_args+=("--label" "$label")
    done < <(echo "$inspect_json" | jq -j '.[0].Config.Labels // {} | to_entries[] | (.key + "=" + .value) + "\u0000"' 2>/dev/null || true)

    # Hostname & Domainname
    local hostname_val
    hostname_val=$(echo "$inspect_json" | jq -r '.[0].Config.Hostname // empty' 2>/dev/null || echo "")
    local domainname
    domainname=$(echo "$inspect_json" | jq -r '.[0].Config.Domainname // empty' 2>/dev/null || echo "")
    [ -n "$hostname_val" ] && run_args+=("--hostname" "$hostname_val")
    [ -n "$domainname" ] && run_args+=("--domainname" "$domainname")

    # Working directory
    local workdir
    workdir=$(echo "$inspect_json" | jq -r '.[0].Config.WorkingDir // empty' 2>/dev/null || echo "")
    [ -n "$workdir" ] && run_args+=("-w" "$workdir")

    # User
    local user
    user=$(echo "$inspect_json" | jq -r '.[0].Config.User // empty' 2>/dev/null || echo "")
    [ -n "$user" ] && run_args+=("--user" "$user")

    # Privileged mode
    local privileged
    privileged=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Privileged' 2>/dev/null || echo "false")
    [ "$privileged" = "true" ] && run_args+=("--privileged")

    # PID mode
    local pid_mode
    pid_mode=$(echo "$inspect_json" | jq -r '.[0].HostConfig.PidMode // empty' 2>/dev/null || echo "")
    [ -n "$pid_mode" ] && run_args+=("--pid" "$pid_mode")

    # Capabilities
    local cap_adds
    cap_adds=$(echo "$inspect_json" | jq -r '.[0].HostConfig.CapAdd[]?' 2>/dev/null || echo "")
    while IFS= read -r cap; do
        [ -n "$cap" ] && run_args+=("--cap-add" "$cap")
    done <<< "$cap_adds"

    local cap_drops
    cap_drops=$(echo "$inspect_json" | jq -r '.[0].HostConfig.CapDrop[]?' 2>/dev/null || echo "")
    while IFS= read -r cap; do
        [ -n "$cap" ] && run_args+=("--cap-drop" "$cap")
    done <<< "$cap_drops"

    # Devices
    local devices
    devices=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Devices[]? | .PathOnHost + ":" + .PathInContainer + (if .CgroupPermissions != "rwm" then ":" + .CgroupPermissions else "" end)' 2>/dev/null || echo "")
    while IFS= read -r device; do
        [ -n "$device" ] && run_args+=("--device" "$device")
    done <<< "$devices"

    # ShmSize
    local shm_size
    shm_size=$(echo "$inspect_json" | jq -r '.[0].HostConfig.ShmSize // 0' 2>/dev/null || echo "0")
    if [ "$shm_size" -gt 67108864 ]; then # Larger than default 64MB
        run_args+=("--shm-size" "$shm_size")
    fi

    # Resource Limits (Memory & CPU)
    local memory_limit
    memory_limit=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Memory // 0' 2>/dev/null || echo "0")
    if [ "$memory_limit" -gt 0 ]; then
        run_args+=("--memory" "${memory_limit}b")
    fi

    local nano_cpus
    nano_cpus=$(echo "$inspect_json" | jq -r '.[0].HostConfig.NanoCpus // 0' 2>/dev/null || echo "0")
    if [ "$nano_cpus" -gt 0 ]; then
        local cpus_val
        cpus_val=$(awk -v n="$nano_cpus" 'BEGIN { printf "%.2f", n / 1000000000 }' 2>/dev/null | sed 's/\.00$//' || echo "")
        [ -n "$cpus_val" ] && run_args+=("--cpus" "$cpus_val")
    fi

    # Extra Hosts (--add-host)
    local extra_hosts
    extra_hosts=$(echo "$inspect_json" | jq -r '.[0].HostConfig.ExtraHosts[]?' 2>/dev/null || echo "")
    while IFS= read -r extra_host; do
        [ -n "$extra_host" ] && run_args+=("--add-host" "$extra_host")
    done <<< "$extra_hosts"

    # Custom DNS
    local dns_servers
    dns_servers=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Dns[]?' 2>/dev/null || echo "")
    while IFS= read -r dns; do
        [ -n "$dns" ] && run_args+=("--dns" "$dns")
    done <<< "$dns_servers"

    # Sysctls
    local sysctls
    sysctls=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Sysctls // {} | to_entries[] | .key + "=" + .value' 2>/dev/null || echo "")
    while IFS= read -r sysctl; do
        [ -n "$sysctl" ] && run_args+=("--sysctl" "$sysctl")
    done <<< "$sysctls"

    # Extract Entrypoint array properly
    local entrypoint_bin=""
    local -a entrypoint_args=()
    entrypoint_bin=$(echo "$inspect_json" | jq -r '.[0].Config.Entrypoint[0] // empty' 2>/dev/null || echo "")
    if [ -n "$entrypoint_bin" ]; then
        while IFS= read -r arg; do
            [ -n "$arg" ] && entrypoint_args+=("$arg")
        done < <(echo "$inspect_json" | jq -r '.[0].Config.Entrypoint[1:][]?' 2>/dev/null || true)
    fi

    # Extract Command array properly
    local -a cmd_args=()
    while IFS= read -r arg; do
        [ -n "$arg" ] && cmd_args+=("$arg")
    done < <(echo "$inspect_json" | jq -r '.[0].Config.Cmd[]?' 2>/dev/null || true)

    # Stop timeout
    local stop_timeout="${SYSTOWER_DOCKER_STOP_TIMEOUT:-30}"
    local label_timeout
    label_timeout=$(get_container_label "$container_id" "systower.stop-timeout")
    [ -n "$label_timeout" ] && stop_timeout="$label_timeout"

    # Stop the running container
    log_info "Stopping container '$container_name' (timeout: ${stop_timeout}s)..."
    if ! docker stop -t "${stop_timeout}" "$container_id" > /dev/null 2>&1; then
        log_error "Failed to stop container '$container_name'"
        return 1
    fi

    # Rename old container to backup (preserves container in case of failure)
    local backup_name="${container_name}_systower_bak"
    docker rm -f "$backup_name" > /dev/null 2>&1 || true
    if ! docker rename "$container_id" "$backup_name" > /dev/null 2>&1; then
        log_error "Failed to rename container '$container_name' to backup"
        docker start "$container_id" > /dev/null 2>&1 || true
        return 1
    fi

    # Build the run command
    local -a full_cmd=("docker" "run" "-d")
    full_cmd+=("${run_args[@]}")

    if [ -n "$entrypoint_bin" ]; then
        full_cmd+=("--entrypoint" "$entrypoint_bin")
    fi

    full_cmd+=("$image_name")

    # Append additional entrypoint arguments (e.g. "--")
    if [ "${#entrypoint_args[@]}" -gt 0 ]; then
        full_cmd+=("${entrypoint_args[@]}")
    fi

    # Append command arguments
    if [ "${#cmd_args[@]}" -gt 0 ]; then
        full_cmd+=("${cmd_args[@]}")
    fi

    # Start new container
    log_info "Starting new container '$container_name'..."
    local run_output=""
    if run_output=$("${full_cmd[@]}" 2>&1); then
        # Reconnect to extra networks
        if [ -n "$extra_networks" ]; then
            while IFS= read -r net; do
                if [ -n "$net" ] && [ "$net" != "$network_mode" ]; then
                    log_debug "Reconnecting '$container_name' to network '$net'"
                    docker network connect "$net" "$container_name" 2>/dev/null || true
                fi
            done <<< "$extra_networks"
        fi

        # Verify container health / running status post-update
        if ! check_container_health "$container_name"; then
            log_error "❌ Container '$container_name' failed health check after update!"
            notify_update_failed "$container_name" "Health check failed after restart"

            # Instant Rollback: restore backup container
            log_warn "🔄 Rolling back '$container_name' to previous container state..."
            docker rm -f "$container_name" > /dev/null 2>&1 || true
            docker rename "$backup_name" "$container_name" > /dev/null 2>&1 || true
            docker start "$container_name" > /dev/null 2>&1 || true
            notify_rollback "$container_name" "Health check failed (reverted to previous image)"
            return 1
        fi

        # Remove backup container on success
        docker rm -f "$backup_name" > /dev/null 2>&1 || true

        log_info "✅ Container '$container_name' successfully updated!"
        notify_update_success "$container_name"
        return 0
    else
        log_error "❌ Failed to start new container '$container_name'"
        log_error "Docker error: $run_output"
        notify_update_failed "$container_name" "Failed to start: $run_output"

        # Instant Rollback: restore backup container
        log_warn "🔄 Rolling back '$container_name' to previous container state..."
        docker rm -f "$container_name" > /dev/null 2>&1 || true
        docker rename "$backup_name" "$container_name" > /dev/null 2>&1 || true
        docker start "$container_name" > /dev/null 2>&1 || true
        notify_rollback "$container_name" "New image failed to start"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# Main update loop
# ----------------------------------------------------------------------------

# Run the Docker update process
run_docker_updates() {
    log_section "🐳 Docker Container Updates"

    # Verify Docker access
    if ! check_docker_socket; then
        log_error "Cannot access Docker. Skipping Docker updates."
        return 1
    fi

    # Get list of running containers
    local container_ids
    container_ids=$(docker ps -q --no-trunc 2>/dev/null || echo "")

    if [ -z "$container_ids" ]; then
        log_info "No running containers found."
        return 0
    fi

    local total=0
    local updated=0
    local skipped=0
    local failed=0
    local up_to_date=0

    while IFS= read -r container_id; do
        [ -z "$container_id" ] && continue

        total=$((total + 1))
        local container_name
        container_name=$(get_container_name "$container_id")
        local image_name
        image_name=$(get_container_image "$container_id")

        log_info "Checking: $container_name ($image_name)"

        # Apply filters
        if ! should_update_container "$container_id"; then
            skipped=$((skipped + 1))
            continue
        fi

        # Pull latest image
        log_debug "Pulling latest image for '$image_name'..."
        if ! docker pull "$image_name" > /dev/null 2>&1; then
            log_warn "Failed to pull image '$image_name'. Skipping '$container_name'."
            failed=$((failed + 1))
            continue
        fi

        # Compare image IDs
        local running_id
        running_id=$(get_running_image_id "$container_id")
        local latest_id
        latest_id=$(get_latest_image_id "$image_name")

        if [ "$running_id" = "$latest_id" ]; then
            log_info "  ✓ '$container_name' is up to date."
            up_to_date=$((up_to_date + 1))
            continue
        fi

        log_info "  ↑ Update available for '$container_name'"

        # Monitor-only mode
        if is_true "${SYSTOWER_DOCKER_MONITOR_ONLY:-false}"; then
            log_info "  👁 Monitor mode: update detected but not applied."
            updated=$((updated + 1))
            continue
        fi

        # Dry run mode
        if is_true "${SYSTOWER_DRY_RUN:-false}"; then
            log_info "  🔍 Dry run: would update '$container_name'"
            updated=$((updated + 1))
            continue
        fi

        # Store old image ID for cleanup
        local old_image_id="$running_id"

        # Recreate container directly via Docker API
        if recreate_container "$container_id"; then
            updated=$((updated + 1))

            # Clean up old image
            if is_true "${SYSTOWER_DOCKER_CLEANUP:-true}"; then
                log_debug "Cleaning up old image: $old_image_id"
                docker rmi "$old_image_id" > /dev/null 2>&1 || true
            fi
        else
            failed=$((failed + 1))
        fi

    done <<< "$container_ids"

    # Summary
    log_info ""
    log_info "📊 Docker Update Summary:"
    log_info "  Total containers:   $total"
    log_info "  Up to date:         $up_to_date"
    log_info "  Updated:            $updated"
    log_info "  Skipped:            $skipped"
    log_info "  Failed:             $failed"
    log_info ""

    # Export for summary notification
    export _DOCKER_UPDATED="$updated"
    export _DOCKER_FAILED="$failed"

    [ "$failed" -eq 0 ]
}
