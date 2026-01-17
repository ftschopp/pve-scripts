#!/bin/bash
# PVE Orchestrator - Common Functions
# https://github.com/ftschopp/pve-scripts

# Colors
readonly RD='\033[0;31m'
readonly GN='\033[0;32m'
readonly YW='\033[0;33m'
readonly BL='\033[0;34m'
readonly CY='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Paths
readonly LOG_FILE="/var/log/pve-orchestrator.log"
readonly CONFIG_DIR="/etc/pve-orchestrator"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yaml"
readonly INSTALL_DIR="/opt/pve-orchestrator"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${GN}[INFO]${NC} $*"
}

log_warn() {
    log "WARN" "$*"
    echo -e "${YW}[WARN]${NC} $*"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RD}[ERROR]${NC} $*" >&2
}

log_debug() {
    log "DEBUG" "$*"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CY}[DEBUG]${NC} $*"
    fi
}

# Print header
print_header() {
    echo -e "${BL}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║           PVE Orchestrator - by ftschopp              ║"
    echo "║     https://github.com/ftschopp/pve-scripts           ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if running on Proxmox VE
check_proxmox() {
    if ! command -v pveversion &> /dev/null; then
        log_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    log_info "Detected Proxmox VE: $(pveversion --verbose | head -1)"
}

# Check if yq is installed
check_yq() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed"
        return 1
    fi
    return 0
}

# Install yq if not present
install_yq() {
    if check_yq; then
        log_debug "yq is already installed"
        return 0
    fi

    log_info "Installing yq..."
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac

    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"
    if wget -qO /usr/local/bin/yq "$yq_url"; then
        chmod +x /usr/local/bin/yq
        log_info "yq installed successfully"
        return 0
    else
        log_error "Failed to install yq"
        return 1
    fi
}

# Read YAML config value
# Usage: config_get "truenas.vmid"
config_get() {
    local key="$1"
    local default="${2:-}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        echo "$default"
        return 1
    fi

    local value
    value=$(yq eval ".${key} // \"\"" "$CONFIG_FILE" 2>/dev/null)

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Read YAML array length
# Usage: config_array_len "containers"
config_array_len() {
    local key="$1"
    yq eval ".${key} | length" "$CONFIG_FILE" 2>/dev/null || echo "0"
}

# Read YAML array item
# Usage: config_array_get "containers" 0 "ctid"
config_array_get() {
    local array="$1"
    local index="$2"
    local key="$3"
    local default="${4:-}"

    local value
    value=$(yq eval ".${array}[${index}].${key} // \"\"" "$CONFIG_FILE" 2>/dev/null)

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Wait for a condition with timeout
# Usage: wait_for "description" timeout_seconds command [args...]
wait_for() {
    local description="$1"
    local timeout="$2"
    shift 2
    local cmd=("$@")

    local elapsed=0
    local interval=5

    log_info "Waiting for ${description} (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        if "${cmd[@]}" &>/dev/null; then
            log_info "${description} - ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        log_debug "Still waiting for ${description}... (${elapsed}s/${timeout}s)"
    done

    log_error "Timeout waiting for ${description}"
    return 1
}

# Check TCP port
# Usage: check_tcp_port host port
check_tcp_port() {
    local host="$1"
    local port="$2"
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
}

# Check ping
# Usage: check_ping host
check_ping() {
    local host="$1"
    ping -c 1 -W 5 "$host" &>/dev/null
}

# Check HTTP endpoint
# Usage: check_http url
check_http() {
    local url="$1"
    curl -sf -o /dev/null --connect-timeout 5 "$url"
}
