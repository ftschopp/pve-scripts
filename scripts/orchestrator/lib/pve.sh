#!/bin/bash
# PVE Orchestrator - Proxmox VE Functions
# https://github.com/ftschopp/pve-scripts

# Get VM status
# Usage: vm_status vmid
vm_status() {
    local vmid="$1"
    qm status "$vmid" 2>/dev/null | awk '{print $2}'
}

# Check if VM exists
# Usage: vm_exists vmid
vm_exists() {
    local vmid="$1"
    qm status "$vmid" &>/dev/null
}

# Start a VM
# Usage: vm_start vmid
vm_start() {
    local vmid="$1"

    if ! vm_exists "$vmid"; then
        log_error "VM $vmid does not exist"
        return 1
    fi

    local status
    status=$(vm_status "$vmid")

    if [[ "$status" == "running" ]]; then
        log_info "VM $vmid is already running"
        return 0
    fi

    log_info "Starting VM $vmid..."
    if qm start "$vmid"; then
        log_info "VM $vmid start command issued"
        return 0
    else
        log_error "Failed to start VM $vmid"
        return 1
    fi
}

# Stop a VM
# Usage: vm_stop vmid [timeout]
vm_stop() {
    local vmid="$1"
    local timeout="${2:-120}"

    if ! vm_exists "$vmid"; then
        log_warn "VM $vmid does not exist"
        return 0
    fi

    local status
    status=$(vm_status "$vmid")

    if [[ "$status" == "stopped" ]]; then
        log_info "VM $vmid is already stopped"
        return 0
    fi

    log_info "Stopping VM $vmid (timeout: ${timeout}s)..."
    if qm shutdown "$vmid" --timeout "$timeout"; then
        log_info "VM $vmid stopped successfully"
        return 0
    else
        log_warn "Graceful shutdown failed, forcing stop..."
        qm stop "$vmid"
        return $?
    fi
}

# Wait for VM to be running
# Usage: vm_wait_running vmid timeout
vm_wait_running() {
    local vmid="$1"
    local timeout="${2:-120}"

    wait_for "VM $vmid to be running" "$timeout" test "$(vm_status "$vmid")" == "running"
}

# Wait for VM QEMU guest agent
# Usage: vm_wait_agent vmid timeout
vm_wait_agent() {
    local vmid="$1"
    local timeout="${2:-300}"

    wait_for "VM $vmid guest agent" "$timeout" qm agent "$vmid" ping
}

# Get container status
# Usage: ct_status ctid
ct_status() {
    local ctid="$1"
    pct status "$ctid" 2>/dev/null | awk '{print $2}'
}

# Check if container exists
# Usage: ct_exists ctid
ct_exists() {
    local ctid="$1"
    pct status "$ctid" &>/dev/null
}

# Start a container
# Usage: ct_start ctid
ct_start() {
    local ctid="$1"

    if ! ct_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    local status
    status=$(ct_status "$ctid")

    if [[ "$status" == "running" ]]; then
        log_info "Container $ctid is already running"
        return 0
    fi

    log_info "Starting container $ctid..."
    if pct start "$ctid"; then
        log_info "Container $ctid started successfully"
        return 0
    else
        log_error "Failed to start container $ctid"
        return 1
    fi
}

# Stop a container
# Usage: ct_stop ctid [timeout]
ct_stop() {
    local ctid="$1"
    local timeout="${2:-60}"

    if ! ct_exists "$ctid"; then
        log_warn "Container $ctid does not exist"
        return 0
    fi

    local status
    status=$(ct_status "$ctid")

    if [[ "$status" == "stopped" ]]; then
        log_info "Container $ctid is already stopped"
        return 0
    fi

    log_info "Stopping container $ctid (timeout: ${timeout}s)..."
    if pct shutdown "$ctid" --timeout "$timeout"; then
        log_info "Container $ctid stopped successfully"
        return 0
    else
        log_warn "Graceful shutdown failed, forcing stop..."
        pct stop "$ctid"
        return $?
    fi
}

# Wait for container to be running
# Usage: ct_wait_running ctid timeout
ct_wait_running() {
    local ctid="$1"
    local timeout="${2:-60}"

    wait_for "Container $ctid to be running" "$timeout" test "$(ct_status "$ctid")" == "running"
}

# Check if a path is mounted
# Usage: is_mounted path
is_mounted() {
    local path="$1"
    mountpoint -q "$path" 2>/dev/null
}

# Mount NFS share
# Usage: mount_nfs source target [options]
mount_nfs() {
    local source="$1"
    local target="$2"
    local options="${3:-rw,soft,intr}"

    if is_mounted "$target"; then
        log_info "NFS $target is already mounted"
        return 0
    fi

    # Create mount point if it doesn't exist
    if [[ ! -d "$target" ]]; then
        log_debug "Creating mount point: $target"
        mkdir -p "$target"
    fi

    log_info "Mounting NFS $source -> $target"
    if mount -t nfs -o "$options" "$source" "$target"; then
        log_info "NFS mounted successfully: $target"
        return 0
    else
        log_error "Failed to mount NFS: $source -> $target"
        return 1
    fi
}

# Mount CIFS share
# Usage: mount_cifs source target [options] [credentials_file]
mount_cifs() {
    local source="$1"
    local target="$2"
    local options="${3:-rw,vers=3.0}"
    local credentials="${4:-}"

    if is_mounted "$target"; then
        log_info "CIFS $target is already mounted"
        return 0
    fi

    # Create mount point if it doesn't exist
    if [[ ! -d "$target" ]]; then
        log_debug "Creating mount point: $target"
        mkdir -p "$target"
    fi

    # Add credentials if provided
    if [[ -n "$credentials" && -f "$credentials" ]]; then
        options="${options},credentials=${credentials}"
    fi

    log_info "Mounting CIFS $source -> $target"
    if mount -t cifs -o "$options" "$source" "$target"; then
        log_info "CIFS mounted successfully: $target"
        return 0
    else
        log_error "Failed to mount CIFS: $source -> $target"
        return 1
    fi
}

# Unmount a path
# Usage: do_unmount path
do_unmount() {
    local path="$1"

    if ! is_mounted "$path"; then
        log_debug "$path is not mounted"
        return 0
    fi

    log_info "Unmounting $path..."
    if umount "$path"; then
        log_info "Unmounted successfully: $path"
        return 0
    else
        log_error "Failed to unmount: $path"
        return 1
    fi
}

# Health check based on type
# Usage: health_check type host [port_or_path]
health_check() {
    local check_type="$1"
    local host="$2"
    local port_or_path="${3:-}"

    case "$check_type" in
        tcp)
            if [[ -z "$port_or_path" ]]; then
                log_error "TCP health check requires a port"
                return 1
            fi
            check_tcp_port "$host" "$port_or_path"
            ;;
        ping)
            check_ping "$host"
            ;;
        http)
            local url="${host}"
            if [[ ! "$url" =~ ^https?:// ]]; then
                url="http://${host}"
            fi
            if [[ -n "$port_or_path" ]]; then
                url="${url}:${port_or_path}"
            fi
            check_http "$url"
            ;;
        *)
            log_error "Unknown health check type: $check_type"
            return 1
            ;;
    esac
}
