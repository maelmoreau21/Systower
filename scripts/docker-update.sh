#!/usr/bin/env bash
# ============================================================================
# Systower — Docker Container Update Engine
# ============================================================================
# Detects and applies updates to Docker containers by pulling the latest
# image, comparing IDs, and recreating containers with their original config.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

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

    # Never update Systower itself
    local self_id
    self_id=$(cat /proc/self/cgroup 2>/dev/null | grep -o '[0-9a-f]\{64\}' | head -n 1 || echo "")
    if [ -n "$self_id" ] && [ "$container_id" = "$self_id" ]; then
        log_debug "Skipping self (Systower container)"
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
# Container recreation
# ----------------------------------------------------------------------------

# Recreate a container with the latest image while preserving config
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

    # Extract network settings
    local networks
    networks=$(echo "$inspect_json" | jq -r '.[0].NetworkSettings.Networks | keys[]' 2>/dev/null || echo "")

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

    # Environment variables
    local envs
    envs=$(echo "$inspect_json" | jq -r '.[0].Config.Env[]?' 2>/dev/null || echo "")
    while IFS= read -r env; do
        if [ -n "$env" ]; then
            run_args+=("-e" "$env")
        fi
    done <<< "$envs"

    # Port bindings
    local port_bindings
    port_bindings=$(echo "$inspect_json" | jq -r '
        .[0].HostConfig.PortBindings // {} | to_entries[] |
        .key as $container_port |
        .value[]? |
        (if .HostIp != "" and .HostIp != "0.0.0.0" then .HostIp + ":" else "" end) +
        (if .HostPort != "" then .HostPort + ":" else "" end) +
        $container_port
    ' 2>/dev/null || echo "")
    while IFS= read -r binding; do
        if [ -n "$binding" ]; then
            run_args+=("-p" "$binding")
        fi
    done <<< "$port_bindings"

    # Volume mounts (binds)
    local binds
    binds=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Binds[]?' 2>/dev/null || echo "")
    while IFS= read -r bind; do
        if [ -n "$bind" ]; then
            run_args+=("-v" "$bind")
        fi
    done <<< "$binds"

    # Named volume mounts (Mounts of type volume)
    local volume_mounts
    volume_mounts=$(echo "$inspect_json" | jq -r '
        .[0].Mounts[]? | select(.Type == "volume") |
        .Name + ":" + .Destination + (if .RW == false then ":ro" else "" end)
    ' 2>/dev/null || echo "")
    while IFS= read -r mount; do
        if [ -n "$mount" ]; then
            # Check it's not already in binds
            if ! echo "$binds" | grep -q "$mount"; then
                run_args+=("-v" "$mount")
            fi
        fi
    done <<< "$volume_mounts"

    # Labels (preserve all labels)
    local labels
    labels=$(echo "$inspect_json" | jq -r '.[0].Config.Labels // {} | to_entries[] | .key + "=" + .value' 2>/dev/null || echo "")
    while IFS= read -r label; do
        if [ -n "$label" ]; then
            run_args+=("--label" "$label")
        fi
    done <<< "$labels"

    # Hostname
    local hostname
    hostname=$(echo "$inspect_json" | jq -r '.[0].Config.Hostname // empty' 2>/dev/null || echo "")
    local domainname
    domainname=$(echo "$inspect_json" | jq -r '.[0].Config.Domainname // empty' 2>/dev/null || echo "")
    if [ -n "$hostname" ]; then
        run_args+=("--hostname" "$hostname")
    fi
    if [ -n "$domainname" ]; then
        run_args+=("--domainname" "$domainname")
    fi

    # Working directory
    local workdir
    workdir=$(echo "$inspect_json" | jq -r '.[0].Config.WorkingDir // empty' 2>/dev/null || echo "")
    if [ -n "$workdir" ]; then
        run_args+=("-w" "$workdir")
    fi

    # User
    local user
    user=$(echo "$inspect_json" | jq -r '.[0].Config.User // empty' 2>/dev/null || echo "")
    if [ -n "$user" ]; then
        run_args+=("--user" "$user")
    fi

    # Privileged mode
    local privileged
    privileged=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Privileged' 2>/dev/null || echo "false")
    if [ "$privileged" = "true" ]; then
        run_args+=("--privileged")
    fi

    # Network mode
    local network_mode
    network_mode=$(echo "$inspect_json" | jq -r '.[0].HostConfig.NetworkMode' 2>/dev/null || echo "default")
    if [ "$network_mode" != "default" ] && [ "$network_mode" != "bridge" ]; then
        run_args+=("--network" "$network_mode")
    fi

    # PID mode
    local pid_mode
    pid_mode=$(echo "$inspect_json" | jq -r '.[0].HostConfig.PidMode // empty' 2>/dev/null || echo "")
    if [ -n "$pid_mode" ]; then
        run_args+=("--pid" "$pid_mode")
    fi

    # Capabilities
    local cap_adds
    cap_adds=$(echo "$inspect_json" | jq -r '.[0].HostConfig.CapAdd[]?' 2>/dev/null || echo "")
    while IFS= read -r cap; do
        if [ -n "$cap" ]; then
            run_args+=("--cap-add" "$cap")
        fi
    done <<< "$cap_adds"

    local cap_drops
    cap_drops=$(echo "$inspect_json" | jq -r '.[0].HostConfig.CapDrop[]?' 2>/dev/null || echo "")
    while IFS= read -r cap; do
        if [ -n "$cap" ]; then
            run_args+=("--cap-drop" "$cap")
        fi
    done <<< "$cap_drops"

    # Devices
    local devices
    devices=$(echo "$inspect_json" | jq -r '.[0].HostConfig.Devices[]? | .PathOnHost + ":" + .PathInContainer + (if .CgroupPermissions != "rwm" then ":" + .CgroupPermissions else "" end)' 2>/dev/null || echo "")
    while IFS= read -r device; do
        if [ -n "$device" ]; then
            run_args+=("--device" "$device")
        fi
    done <<< "$devices"

    # Entrypoint (if custom)
    local entrypoint
    entrypoint=$(echo "$inspect_json" | jq -r '.[0].Config.Entrypoint // [] | join(" ")' 2>/dev/null || echo "")

    # Command
    local cmd
    cmd=$(echo "$inspect_json" | jq -r '.[0].Config.Cmd // [] | .[]' 2>/dev/null || echo "")

    # Stop the running container
    log_info "Stopping container '$container_name' (timeout: ${SYSTOWER_DOCKER_STOP_TIMEOUT}s)..."
    if ! docker stop -t "${SYSTOWER_DOCKER_STOP_TIMEOUT}" "$container_id" > /dev/null 2>&1; then
        log_error "Failed to stop container '$container_name'"
        return 1
    fi

    # Remove the old container
    log_info "Removing old container '$container_name'..."
    if ! docker rm "$container_id" > /dev/null 2>&1; then
        log_error "Failed to remove container '$container_name'"
        # Try to restart the old one
        docker start "$container_id" > /dev/null 2>&1 || true
        return 1
    fi

    # Start the new container
    log_info "Starting new container '$container_name'..."

    # Build the full command
    local -a full_cmd=("docker" "run" "-d")
    full_cmd+=("${run_args[@]}")

    # Custom entrypoint
    if [ -n "$entrypoint" ]; then
        full_cmd+=("--entrypoint" "$entrypoint")
    fi

    # Image
    full_cmd+=("$image_name")

    # CMD arguments
    if [ -n "$cmd" ]; then
        while IFS= read -r arg; do
            if [ -n "$arg" ]; then
                full_cmd+=("$arg")
            fi
        done <<< "$cmd"
    fi

    if "${full_cmd[@]}" > /dev/null 2>&1; then
        log_info "✅ Container '$container_name' successfully updated!"
        return 0
    else
        log_error "❌ Failed to start new container '$container_name'"
        log_error "Command was: ${full_cmd[*]}"
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

        # Monitor-only mode: just report, don't update
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

        # Recreate the container
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

    [ "$failed" -eq 0 ]
}
