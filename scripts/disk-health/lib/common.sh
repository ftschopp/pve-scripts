#!/bin/bash
# common.sh - Common functions for disk-health script
# Provides logging, colors, and utility functions

# Colors
readonly RD='\033[0;31m'       # Red (errors, critical)
readonly GN='\033[0;32m'       # Green (good, healthy)
readonly YW='\033[0;33m'       # Yellow (warnings)
readonly BL='\033[0;34m'       # Blue (headers)
readonly MG='\033[0;35m'       # Magenta (info highlights)
readonly CY='\033[0;36m'       # Cyan (debug, details)
readonly NC='\033[0m'          # No color
readonly BOLD='\033[1m'        # Bold text
readonly DIM='\033[2m'         # Dim text

# Status indicators
readonly ICON_OK="[OK]"
readonly ICON_WARN="[!]"
readonly ICON_CRIT="[X]"
readonly ICON_INFO="[i]"

# Logging
LOG_FILE="/var/log/disk-health.log"

# Log to file with timestamp
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
    log "INFO" "$*"
}

log_warn() {
    log "WARN" "$*"
}

log_error() {
    log "ERROR" "$*"
}

# Print functions for console output
print_header() {
    local title="$1"
    local width=70
    echo ""
    echo -e "${BL}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${BL}${BOLD}  $title${NC}"
    echo -e "${BL}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
}

print_subheader() {
    local title="$1"
    echo ""
    echo -e "${CY}${BOLD}── $title ──${NC}"
}

print_ok() {
    echo -e "${GN}${ICON_OK}${NC} $*"
}

print_warn() {
    echo -e "${YW}${ICON_WARN}${NC} $*"
}

print_crit() {
    echo -e "${RD}${ICON_CRIT}${NC} $*"
}

print_info() {
    echo -e "${MG}${ICON_INFO}${NC} $*"
}

print_dim() {
    echo -e "${DIM}    $*${NC}"
}

# Print a key-value pair with formatting
print_kv() {
    local key="$1"
    local value="$2"
    local color="${3:-$NC}"
    printf "  ${DIM}%-20s${NC} ${color}%s${NC}\n" "$key:" "$value"
}

# Print a progress bar
print_bar() {
    local percent="$1"
    local width=30
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local color="$GN"

    if [ "$percent" -ge 90 ]; then
        color="$RD"
    elif [ "$percent" -ge 70 ]; then
        color="$YW"
    fi

    printf "  [${color}"
    printf '█%.0s' $(seq 1 $filled) 2>/dev/null || true
    printf "${NC}${DIM}"
    printf '░%.0s' $(seq 1 $empty) 2>/dev/null || true
    printf "${NC}] ${color}%3d%%${NC}\n" "$percent"
}

# Convert bytes to human readable
bytes_to_human() {
    local bytes="$1"
    if [ -z "$bytes" ] || [ "$bytes" = "0" ]; then
        echo "0 B"
        return
    fi

    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit=0
    local value=$bytes

    while [ "$value" -ge 1024 ] && [ "$unit" -lt 5 ]; do
        value=$((value / 1024))
        unit=$((unit + 1))
    done

    echo "$value ${units[$unit]}"
}

# Convert seconds to human readable time
seconds_to_human() {
    local seconds="$1"
    if [ -z "$seconds" ] || [ "$seconds" = "0" ]; then
        echo "0 seconds"
        return
    fi

    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local mins=$(((seconds % 3600) / 60))

    local result=""
    [ "$days" -gt 0 ] && result="${days}d "
    [ "$hours" -gt 0 ] && result="${result}${hours}h "
    [ "$mins" -gt 0 ] && result="${result}${mins}m"

    echo "${result:-0m}"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RD}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Check if smartctl is available
check_smartctl() {
    if ! command -v smartctl &>/dev/null; then
        return 1
    fi
    return 0
}

# Install smartmontools if not present
install_smartmontools() {
    if ! check_smartctl; then
        echo -e "${YW}Installing smartmontools...${NC}"
        apt-get update -qq && apt-get install -y -qq smartmontools
        if ! check_smartctl; then
            echo -e "${RD}Failed to install smartmontools${NC}"
            exit 1
        fi
        echo -e "${GN}smartmontools installed successfully${NC}"
    fi
}
