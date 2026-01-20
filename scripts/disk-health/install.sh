#!/bin/bash
# Disk Health Monitor - Remote Installer
# https://github.com/ftschopp/pve-scripts
#
# Usage:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"

set -euo pipefail

# Configuration
REPO_RAW_URL="https://raw.githubusercontent.com/ftschopp/pve-scripts/main"
SCRIPT_PATH="scripts/disk-health"
INSTALL_DIR="/opt/disk-health"
SERVICE_NAME="disk-health"

# Source shared build functions
source <(curl -fsSL "${REPO_RAW_URL}/misc/build.func") || source <(wget -qO- "${REPO_RAW_URL}/misc/build.func")

# Print header
print_banner() {
    clear
    echo -e "${BL}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ██████╗ ██╗███████╗██╗  ██╗    ██╗  ██╗███████╗ █████╗ ██╗     ║
║   ██╔══██╗██║██╔════╝██║ ██╔╝    ██║  ██║██╔════╝██╔══██╗██║     ║
║   ██║  ██║██║███████╗█████╔╝     ███████║█████╗  ███████║██║     ║
║   ██║  ██║██║╚════██║██╔═██╗     ██╔══██║██╔══╝  ██╔══██║██║     ║
║   ██████╔╝██║███████║██║  ██╗    ██║  ██║███████╗██║  ██║███████╗║
║   ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝║
║                                                                   ║
║              Disk Health Monitor - SMART Analysis Tool            ║
║              https://github.com/ftschopp/pve-scripts              ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Create directory structure
create_directories() {
    msg_info "Creating directories..."
    mkdir -p "${INSTALL_DIR}/lib"
}

# Download all files
download_files() {
    msg_info "Downloading disk-health files..."

    download_file "${SCRIPT_PATH}/lib/common.sh" "${INSTALL_DIR}/lib/common.sh"
    download_file "${SCRIPT_PATH}/lib/smart.sh" "${INSTALL_DIR}/lib/smart.sh"
    download_file "${SCRIPT_PATH}/service.sh" "${INSTALL_DIR}/service.sh"

    # Set permissions
    chmod +x "${INSTALL_DIR}/lib/common.sh"
    chmod +x "${INSTALL_DIR}/lib/smart.sh"
    chmod +x "${INSTALL_DIR}/service.sh"

    msg_ok "Files downloaded"
}

# Install smartmontools if needed
install_deps() {
    if ! command -v smartctl &>/dev/null; then
        msg_info "Installing smartmontools..."
        apt-get update -qq
        apt-get install -y -qq smartmontools
        msg_ok "smartmontools installed"
    else
        msg_ok "smartmontools already installed"
    fi
}

# Create convenience symlink
create_symlink() {
    rm -f /usr/local/bin/disk-health
    ln -s "${INSTALL_DIR}/service.sh" /usr/local/bin/disk-health
    msg_ok "Created symlink: /usr/local/bin/disk-health"
}

# Print post-install instructions
print_instructions() {
    echo ""
    echo -e "${GN}${BOLD}Installation Complete!${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo ""
    echo "  Show health status of all disks:"
    echo -e "   ${YW}disk-health status${NC}"
    echo ""
    echo "  Quick summary view:"
    echo -e "   ${YW}disk-health summary${NC}"
    echo ""
    echo "  Detailed info for a specific disk:"
    echo -e "   ${YW}disk-health details -d /dev/sda${NC}"
    echo ""
    echo "  Check for critical issues:"
    echo -e "   ${YW}disk-health check${NC}"
    echo ""
    echo "  Output in JSON format:"
    echo -e "   ${YW}disk-health json${NC}"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  disk-health status   - Full status cards for all disks"
    echo "  disk-health summary  - Quick table summary"
    echo "  disk-health details  - Detailed info for one disk"
    echo "  disk-health check    - Check for warnings/issues"
    echo "  disk-health json     - JSON output for automation"
    echo "  disk-health help     - Show help"
    echo ""
    echo -e "${BOLD}Logs:${NC}"
    echo -e "   ${YW}tail -f /var/log/disk-health.log${NC}"
    echo ""
}

# Uninstall function
uninstall() {
    msg_warn "Uninstalling Disk Health Monitor..."

    rm -f /usr/local/bin/disk-health
    rm -rf "${INSTALL_DIR}"

    msg_ok "Uninstalled successfully"
}

# Main installation
main() {
    print_banner

    # Handle uninstall flag
    if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
        check_root
        uninstall
        exit 0
    fi

    msg_info "Starting installation..."
    echo ""

    check_root
    check_debian

    install_deps
    create_directories
    download_files
    create_symlink

    print_instructions
}

main "$@"
