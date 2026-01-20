#!/bin/bash
# service.sh - Disk Health Monitor
# Main script for checking disk and SSD health status
set -euo pipefail

# Script directory detection (follow symlinks)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/smart.sh"

# Script version
readonly VERSION="1.0.0"

# Print banner
print_banner() {
    echo -e "${BL}${BOLD}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║   ██████╗ ██╗███████╗██╗  ██╗    ██╗  ██╗███████╗ █████╗ ██╗     ║
║   ██╔══██╗██║██╔════╝██║ ██╔╝    ██║  ██║██╔════╝██╔══██╗██║     ║
║   ██║  ██║██║███████╗█████╔╝     ███████║█████╗  ███████║██║     ║
║   ██║  ██║██║╚════██║██╔═██╗     ██╔══██║██╔══╝  ██╔══██║██║     ║
║   ██████╔╝██║███████║██║  ██╗    ██║  ██║███████╗██║  ██║███████╗║
║   ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝║
║                                                                   ║
║   Disk Health Monitor - SMART Analysis Tool                       ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Show usage
show_usage() {
    echo "Usage: $(basename "$0") [command] [options]"
    echo ""
    echo "Commands:"
    echo "  status      Show health status of all disks (default)"
    echo "  summary     Show quick summary of all disks"
    echo "  details     Show detailed information for a specific disk"
    echo "  check       Check for critical issues and warnings"
    echo "  json        Output status in JSON format"
    echo "  help        Show this help message"
    echo ""
    echo "Options:"
    echo "  -d, --device    Specify device (e.g., /dev/sda)"
    echo "  -q, --quiet     Quiet mode (minimal output)"
    echo "  -v, --version   Show version"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") status"
    echo "  $(basename "$0") details -d /dev/sda"
    echo "  $(basename "$0") check"
}

# Print disk health card
print_disk_card() {
    local device="$1"
    local name=$(basename "$device")
    local disk_type=$(get_disk_type "$device")
    local model=$(get_disk_model "$device")
    local serial=$(get_disk_serial "$device")
    local size=$(get_disk_size "$device")
    local size_human=$(bytes_to_human "$size")
    local temp=$(get_disk_temperature "$device")
    local health=$(get_smart_health "$device")
    local score=$(calculate_health_score "$device")
    local status=$(get_health_status "$score")
    local hours=$(get_power_on_hours "$device")
    local hours_human=$(seconds_to_human $((hours * 3600)))

    # Determine status color
    local status_color="$GN"
    if [ "$score" -lt 50 ]; then
        status_color="$RD"
    elif [ "$score" -lt 70 ]; then
        status_color="$YW"
    fi

    # Card header
    echo ""
    echo -e "${BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}│${NC} %-12s ${BOLD}│${NC} %-20s ${BOLD}│${NC} ${status_color}%-10s${NC} ${BOLD}│${NC} Score: ${status_color}%3d%%${NC} ${BOLD}│${NC}\n" \
        "$name" "$disk_type" "$status" "$score"
    echo -e "${BOLD}├─────────────────────────────────────────────────────────────────┤${NC}"

    # Model and serial
    printf "${BOLD}│${NC}  Model:  %-55s${BOLD}│${NC}\n" "$model"
    printf "${BOLD}│${NC}  Serial: %-55s${BOLD}│${NC}\n" "$serial"
    echo -e "${BOLD}├─────────────────────────────────────────────────────────────────┤${NC}"

    # Stats
    printf "${BOLD}│${NC}  Size: %-15s  Temp: %-10s  Power On: %-12s${BOLD}│${NC}\n" \
        "$size_human" "${temp}°C" "$hours_human"

    # SMART status
    local smart_color="$GN"
    if [[ "$health" != "PASSED" ]] && [[ "$health" != "OK" ]]; then
        smart_color="$RD"
    fi
    printf "${BOLD}│${NC}  SMART Status: ${smart_color}%-49s${NC}${BOLD}│${NC}\n" "$health"

    # Type-specific info
    if [ "$disk_type" = "SSD" ] || [ "$disk_type" = "NVMe" ]; then
        local life=$(get_ssd_life_remaining "$device")
        local written=$(get_total_bytes_written "$device")
        local written_human=$(bytes_to_human "$written")

        local life_color="$GN"
        if [ "$life" != "N/A" ] && [ -n "$life" ]; then
            if [ "$life" -lt 30 ]; then
                life_color="$RD"
            elif [ "$life" -lt 50 ]; then
                life_color="$YW"
            fi
        fi

        printf "${BOLD}│${NC}  Life Remaining: ${life_color}%-10s${NC}  Total Written: %-20s${BOLD}│${NC}\n" \
            "${life}%" "$written_human"
    else
        # HDD specific
        local reallocated=$(get_reallocated_sectors "$device")
        local pending=$(get_pending_sectors "$device")

        local realloc_color="$GN"
        if [ -n "$reallocated" ] && [ "$reallocated" != "0" ]; then
            realloc_color="$YW"
            [ "$reallocated" -gt 100 ] && realloc_color="$RD"
        fi

        printf "${BOLD}│${NC}  Reallocated Sectors: ${realloc_color}%-8s${NC}  Pending: %-18s${BOLD}│${NC}\n" \
            "${reallocated:-0}" "${pending:-0}"
    fi

    # Warnings
    if has_critical_warnings "$device"; then
        echo -e "${BOLD}├─────────────────────────────────────────────────────────────────┤${NC}"
        printf "${BOLD}│${NC}  ${RD}${BOLD}⚠ WARNING: Critical issues detected!${NC}%-26s${BOLD}│${NC}\n" ""
    fi

    echo -e "${BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"
}

# Print summary table
print_summary() {
    local disks=$(get_disk_list)

    print_header "Disk Health Summary"
    echo ""
    printf "${BOLD}%-12s %-8s %-25s %-10s %-8s %-10s${NC}\n" \
        "DEVICE" "TYPE" "MODEL" "SIZE" "TEMP" "HEALTH"
    echo "────────────────────────────────────────────────────────────────────────────"

    local critical_count=0
    local warning_count=0

    for device in $disks; do
        local name=$(basename "$device")
        local disk_type=$(get_disk_type "$device")
        local model=$(get_disk_model "$device")
        local size=$(get_disk_size "$device")
        local size_human=$(bytes_to_human "$size")
        local temp=$(get_disk_temperature "$device")
        local score=$(calculate_health_score "$device")
        local status=$(get_health_status "$score")

        # Truncate model name
        [ ${#model} -gt 24 ] && model="${model:0:21}..."

        # Color based on health
        local color="$GN"
        if [ "$score" -lt 50 ]; then
            color="$RD"
            ((critical_count++))
        elif [ "$score" -lt 70 ]; then
            color="$YW"
            ((warning_count++))
        fi

        printf "%-12s %-8s %-25s %-10s %-8s ${color}%-10s${NC}\n" \
            "$name" "$disk_type" "$model" "$size_human" "${temp}°C" "$status ($score%)"
    done

    echo ""
    if [ "$critical_count" -gt 0 ]; then
        print_crit "$critical_count disk(s) in critical condition!"
    fi
    if [ "$warning_count" -gt 0 ]; then
        print_warn "$warning_count disk(s) need attention"
    fi
    if [ "$critical_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
        print_ok "All disks are healthy"
    fi
}

# Print detailed disk info
print_details() {
    local device="$1"

    if [ ! -b "$device" ]; then
        print_crit "Device $device not found"
        return 1
    fi

    local name=$(basename "$device")
    local disk_type=$(get_disk_type "$device")
    local model=$(get_disk_model "$device")
    local serial=$(get_disk_serial "$device")
    local firmware=$(get_disk_firmware "$device")
    local size=$(get_disk_size "$device")
    local size_human=$(bytes_to_human "$size")
    local temp=$(get_disk_temperature "$device")
    local health=$(get_smart_health "$device")
    local score=$(calculate_health_score "$device")
    local status=$(get_health_status "$score")
    local hours=$(get_power_on_hours "$device")
    local errors=$(get_smart_error_count "$device")

    print_header "Detailed Information: $name"

    print_subheader "Device Information"
    print_kv "Device" "$device"
    print_kv "Type" "$disk_type"
    print_kv "Model" "$model"
    print_kv "Serial" "$serial"
    print_kv "Firmware" "${firmware:-N/A}"
    print_kv "Capacity" "$size_human"

    print_subheader "Health Status"

    local status_color="$GN"
    [ "$score" -lt 50 ] && status_color="$RD"
    [ "$score" -lt 70 ] && [ "$score" -ge 50 ] && status_color="$YW"

    print_kv "Health Score" "$score%" "$status_color"
    print_kv "Status" "$status" "$status_color"

    local smart_color="$GN"
    [[ "$health" != "PASSED" ]] && [[ "$health" != "OK" ]] && smart_color="$RD"
    print_kv "SMART Status" "$health" "$smart_color"

    print_subheader "Usage Statistics"
    print_kv "Power On Time" "$(seconds_to_human $((hours * 3600))) ($hours hours)"
    print_kv "Temperature" "${temp}°C"
    print_kv "SMART Errors" "$errors"

    if [ "$disk_type" = "SSD" ] || [ "$disk_type" = "NVMe" ]; then
        local life=$(get_ssd_life_remaining "$device")
        local written=$(get_total_bytes_written "$device")

        print_subheader "SSD/NVMe Specific"
        print_kv "Life Remaining" "${life}%"
        print_kv "Total Written" "$(bytes_to_human "$written")"
    else
        local reallocated=$(get_reallocated_sectors "$device")
        local pending=$(get_pending_sectors "$device")
        local uncorrectable=$(get_uncorrectable_sectors "$device")

        print_subheader "HDD Specific"
        print_kv "Reallocated Sectors" "${reallocated:-0}"
        print_kv "Pending Sectors" "${pending:-0}"
        print_kv "Uncorrectable" "${uncorrectable:-0}"
    fi

    print_subheader "SMART Self-Test History"
    local selftest=$(get_smart_selftest "$device")
    if [ -n "$selftest" ]; then
        echo "$selftest" | while read -r line; do
            print_dim "$line"
        done
    else
        print_dim "No self-test history available"
    fi

    # Warnings section
    if has_critical_warnings "$device"; then
        print_subheader "Warnings"
        print_crit "This disk has critical issues that require attention!"

        [[ "$health" != "PASSED" ]] && [[ "$health" != "OK" ]] && \
            print_warn "SMART health check failed"

        local reallocated=$(get_reallocated_sectors "$device")
        [ -n "$reallocated" ] && [ "$reallocated" -gt 100 ] && \
            print_warn "High number of reallocated sectors ($reallocated)"

        local pending=$(get_pending_sectors "$device")
        [ -n "$pending" ] && [ "$pending" -gt 0 ] && \
            print_warn "Pending sectors detected ($pending)"

        local life=$(get_ssd_life_remaining "$device")
        [ "$life" != "N/A" ] && [ -n "$life" ] && [ "$life" -lt 10 ] && \
            print_warn "SSD life remaining is critically low (${life}%)"
    fi

    echo ""
}

# Check all disks for issues
check_disks() {
    local disks=$(get_disk_list)
    local has_issues=0

    print_header "Disk Health Check"
    echo ""

    for device in $disks; do
        local name=$(basename "$device")
        local score=$(calculate_health_score "$device")

        if has_critical_warnings "$device"; then
            print_crit "$name: Critical issues detected (Score: $score%)"
            has_issues=1
        elif [ "$score" -lt 70 ]; then
            print_warn "$name: Disk health is degraded (Score: $score%)"
            has_issues=1
        else
            print_ok "$name: Healthy (Score: $score%)"
        fi
    done

    echo ""

    if [ "$has_issues" -eq 1 ]; then
        echo -e "${YW}Run '$(basename "$0") status' for more details${NC}"
        return 1
    else
        print_ok "All disks are healthy!"
        return 0
    fi
}

# Output as JSON
output_json() {
    local disks=$(get_disk_list)

    echo "{"
    echo '  "timestamp": "'$(date -Iseconds)'",'
    echo '  "disks": ['

    local first=true
    for device in $disks; do
        [ "$first" = true ] && first=false || echo ","

        local name=$(basename "$device")
        local disk_type=$(get_disk_type "$device")
        local model=$(get_disk_model "$device")
        local serial=$(get_disk_serial "$device")
        local size=$(get_disk_size "$device")
        local temp=$(get_disk_temperature "$device")
        local health=$(get_smart_health "$device")
        local score=$(calculate_health_score "$device")
        local hours=$(get_power_on_hours "$device")
        local errors=$(get_smart_error_count "$device")
        local critical=$(has_critical_warnings "$device" && echo "true" || echo "false")

        cat << DISKJSON
    {
      "device": "$device",
      "name": "$name",
      "type": "$disk_type",
      "model": "$model",
      "serial": "$serial",
      "size_bytes": $size,
      "temperature_c": ${temp:-null},
      "smart_status": "$health",
      "health_score": $score,
      "power_on_hours": ${hours:-0},
      "smart_errors": ${errors:-0},
      "critical_warnings": $critical
    }
DISKJSON
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Show all disks status
show_status() {
    local disks=$(get_disk_list)

    print_banner

    if [ -z "$disks" ]; then
        print_warn "No disks found"
        return 1
    fi

    local disk_count=$(echo "$disks" | wc -l)
    print_info "Found $disk_count disk(s)"

    for device in $disks; do
        print_disk_card "$device"
    done

    echo ""
    log_info "Status check completed for $disk_count disk(s)"
}

# Main function
main() {
    local command="${1:-status}"
    local device=""
    local quiet=false

    # Parse arguments
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -d|--device)
                device="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -v|--version)
                echo "Disk Health Monitor v$VERSION"
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check requirements
    check_root
    install_smartmontools

    # Execute command
    case "$command" in
        status)
            show_status
            ;;
        summary)
            print_summary
            ;;
        details)
            if [ -z "$device" ]; then
                echo "Error: Please specify a device with -d /dev/sdX"
                exit 1
            fi
            print_details "$device"
            ;;
        check)
            check_disks
            ;;
        json)
            output_json
            ;;
        help|-h|--help)
            show_usage
            ;;
        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
