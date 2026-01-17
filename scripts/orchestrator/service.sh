#!/bin/bash
# PVE Orchestrator - Main Service Script
# https://github.com/ftschopp/pve-scripts
#
# This script orchestrates the startup and shutdown of:
# 1. TrueNAS VM
# 2. NFS/CIFS mounts
# 3. LXC containers (in specified order)

set -euo pipefail

# Resolve the actual script location (follow symlinks)
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/pve.sh"

# =============================================================================
# Startup Functions
# =============================================================================

start_truenas() {
    local vmid
    local timeout
    local check_type
    local check_host
    local check_port

    vmid=$(config_get "truenas.vmid")
    if [[ -z "$vmid" ]]; then
        log_warn "No TrueNAS VM configured, skipping..."
        return 0
    fi

    timeout=$(config_get "truenas.wait_timeout" "300")
    check_type=$(config_get "truenas.health_check.type" "ping")
    check_host=$(config_get "truenas.health_check.host")
    check_port=$(config_get "truenas.health_check.port" "")

    log_info "Starting TrueNAS VM (VMID: $vmid)..."

    # Start the VM
    if ! vm_start "$vmid"; then
        log_error "Failed to start TrueNAS VM"
        return 1
    fi

    # Wait for VM to be running
    if ! vm_wait_running "$vmid" 60; then
        log_error "TrueNAS VM failed to start"
        return 1
    fi

    # Wait for health check
    if [[ -n "$check_host" ]]; then
        log_info "Waiting for TrueNAS to be accessible..."
        if ! wait_for "TrueNAS health check" "$timeout" health_check "$check_type" "$check_host" "$check_port"; then
            log_error "TrueNAS health check failed"
            return 1
        fi
    fi

    log_info "TrueNAS is ready"
    return 0
}

start_mounts() {
    local count
    count=$(config_array_len "mounts")

    if [[ "$count" -eq 0 ]]; then
        log_info "No mounts configured, skipping..."
        return 0
    fi

    log_info "Configuring $count mount(s)..."

    for ((i = 0; i < count; i++)); do
        local mount_type
        local source
        local target
        local options
        local credentials

        mount_type=$(config_array_get "mounts" "$i" "type")
        source=$(config_array_get "mounts" "$i" "source")
        target=$(config_array_get "mounts" "$i" "target")
        options=$(config_array_get "mounts" "$i" "options" "")
        credentials=$(config_array_get "mounts" "$i" "credentials" "")

        case "$mount_type" in
            nfs)
                if [[ -n "$options" ]]; then
                    mount_nfs "$source" "$target" "$options"
                else
                    mount_nfs "$source" "$target"
                fi
                ;;
            cifs)
                if [[ -n "$options" ]]; then
                    mount_cifs "$source" "$target" "$options" "$credentials"
                else
                    mount_cifs "$source" "$target" "" "$credentials"
                fi
                ;;
            *)
                log_error "Unknown mount type: $mount_type"
                ;;
        esac
    done

    log_info "All mounts configured"
    return 0
}

start_containers() {
    local count
    count=$(config_array_len "containers")

    if [[ "$count" -eq 0 ]]; then
        log_info "No containers configured, skipping..."
        return 0
    fi

    log_info "Starting $count container(s)..."

    for ((i = 0; i < count; i++)); do
        local ctid
        local name
        local wait_time
        local depends_on_mount

        ctid=$(config_array_get "containers" "$i" "ctid")
        name=$(config_array_get "containers" "$i" "name" "container-$ctid")
        wait_time=$(config_array_get "containers" "$i" "wait" "0")
        depends_on_mount=$(config_array_get "containers" "$i" "depends_on_mount" "")

        # Check mount dependency
        if [[ -n "$depends_on_mount" ]]; then
            if ! is_mounted "$depends_on_mount"; then
                log_warn "Container $name ($ctid) depends on $depends_on_mount which is not mounted, skipping..."
                continue
            fi
        fi

        log_info "Starting container: $name ($ctid)"
        if ct_start "$ctid"; then
            if [[ "$wait_time" -gt 0 ]]; then
                log_debug "Waiting ${wait_time}s before next container..."
                sleep "$wait_time"
            fi
        else
            log_error "Failed to start container: $name ($ctid)"
        fi
    done

    log_info "Container startup complete"
    return 0
}

# =============================================================================
# Shutdown Functions
# =============================================================================

stop_containers() {
    local count
    local timeout

    count=$(config_array_len "containers")
    timeout=$(config_get "shutdown.container_timeout" "30")

    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    log_info "Stopping $count container(s)..."

    # Stop in reverse order
    for ((i = count - 1; i >= 0; i--)); do
        local ctid
        local name

        ctid=$(config_array_get "containers" "$i" "ctid")
        name=$(config_array_get "containers" "$i" "name" "container-$ctid")

        log_info "Stopping container: $name ($ctid)"
        ct_stop "$ctid" "$timeout"
    done

    log_info "All containers stopped"
    return 0
}

stop_mounts() {
    local unmount_shares
    unmount_shares=$(config_get "shutdown.unmount_shares" "true")

    if [[ "$unmount_shares" != "true" ]]; then
        log_info "Skipping unmount (disabled in config)"
        return 0
    fi

    local count
    count=$(config_array_len "mounts")

    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    log_info "Unmounting $count share(s)..."

    # Unmount in reverse order
    for ((i = count - 1; i >= 0; i--)); do
        local target
        target=$(config_array_get "mounts" "$i" "target")
        do_unmount "$target"
    done

    log_info "All shares unmounted"
    return 0
}

stop_truenas() {
    local vmid
    local timeout

    vmid=$(config_get "truenas.vmid")
    if [[ -z "$vmid" ]]; then
        return 0
    fi

    timeout=$(config_get "shutdown.vm_timeout" "120")

    log_info "Stopping TrueNAS VM (VMID: $vmid)..."
    vm_stop "$vmid" "$timeout"

    log_info "TrueNAS VM stopped"
    return 0
}

# =============================================================================
# Main Functions
# =============================================================================

do_start() {
    print_header
    log_info "Starting PVE Orchestrator..."

    # Check config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Please copy the example config and customize it:"
        log_error "  cp ${SCRIPT_DIR}/config.yaml.example $CONFIG_FILE"
        exit 1
    fi

    # Check yq is available
    if ! check_yq; then
        log_error "yq is required to parse configuration"
        exit 1
    fi

    # Execute startup sequence
    start_truenas
    start_mounts
    start_containers

    log_info "PVE Orchestrator startup complete"
}

do_stop() {
    print_header
    log_info "Stopping PVE Orchestrator..."

    # Check config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Execute shutdown sequence (reverse order)
    stop_containers
    stop_mounts
    stop_truenas

    log_info "PVE Orchestrator shutdown complete"
}

do_status() {
    print_header
    echo -e "${BOLD}PVE Orchestrator Status${NC}"
    echo ""

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RD}Configuration file not found${NC}"
        exit 1
    fi

    # TrueNAS VM status
    local vmid
    vmid=$(config_get "truenas.vmid")
    if [[ -n "$vmid" ]]; then
        local status
        status=$(vm_status "$vmid")
        echo -e "TrueNAS VM ($vmid): ${BOLD}${status}${NC}"
    fi

    echo ""

    # Mounts status
    echo -e "${BOLD}Mounts:${NC}"
    local mount_count
    mount_count=$(config_array_len "mounts")
    for ((i = 0; i < mount_count; i++)); do
        local target
        target=$(config_array_get "mounts" "$i" "target")
        if is_mounted "$target"; then
            echo -e "  $target: ${GN}mounted${NC}"
        else
            echo -e "  $target: ${RD}not mounted${NC}"
        fi
    done

    echo ""

    # Containers status
    echo -e "${BOLD}Containers:${NC}"
    local ct_count
    ct_count=$(config_array_len "containers")
    for ((i = 0; i < ct_count; i++)); do
        local ctid
        local name
        local status

        ctid=$(config_array_get "containers" "$i" "ctid")
        name=$(config_array_get "containers" "$i" "name" "container-$ctid")
        status=$(ct_status "$ctid")

        if [[ "$status" == "running" ]]; then
            echo -e "  $name ($ctid): ${GN}${status}${NC}"
        else
            echo -e "  $name ($ctid): ${RD}${status}${NC}"
        fi
    done
}

usage() {
    echo "Usage: $0 {start|stop|restart|status}"
    echo ""
    echo "Commands:"
    echo "  start   - Start TrueNAS VM, mount shares, and start containers"
    echo "  stop    - Stop containers, unmount shares, and stop TrueNAS VM"
    echo "  restart - Stop and then start all services"
    echo "  status  - Show status of all managed resources"
    exit 1
}

# =============================================================================
# Main
# =============================================================================

main() {
    check_root

    case "${1:-}" in
        start)
            do_start
            ;;
        stop)
            do_stop
            ;;
        restart)
            do_stop
            do_start
            ;;
        status)
            do_status
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
