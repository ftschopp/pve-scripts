#!/bin/bash
# PVE Orchestrator - Remote Installer
# https://github.com/ftschopp/pve-scripts
#
# Usage:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"

set -euo pipefail

# Configuration
REPO_RAW_URL="https://raw.githubusercontent.com/ftschopp/pve-scripts/main"
SCRIPT_PATH="scripts/orchestrator"
INSTALL_DIR="/opt/pve-orchestrator"
CONFIG_DIR="/etc/pve-orchestrator"
SERVICE_NAME="pve-orchestrator"

# Source shared build functions
source <(curl -fsSL "${REPO_RAW_URL}/misc/build.func") || source <(wget -qO- "${REPO_RAW_URL}/misc/build.func")

# Print header
print_banner() {
    clear
    echo -e "${BL}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ██████╗ ██╗   ██╗███████╗     ██████╗ ██████╗  ██████╗██╗  ██╗  ║
║   ██╔══██╗██║   ██║██╔════╝    ██╔═══██╗██╔══██╗██╔════╝██║  ██║  ║
║   ██████╔╝██║   ██║█████╗      ██║   ██║██████╔╝██║     ███████║  ║
║   ██╔═══╝ ╚██╗ ██╔╝██╔══╝      ██║   ██║██╔══██╗██║     ██╔══██║  ║
║   ██║      ╚████╔╝ ███████╗    ╚██████╔╝██║  ██║╚██████╗██║  ██║  ║
║   ╚═╝       ╚═══╝  ╚══════╝     ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝  ║
║                                                                   ║
║              PVE Orchestrator - VM & Container Manager            ║
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
    mkdir -p "${CONFIG_DIR}"
}

# Download all files
download_files() {
    msg_info "Downloading orchestrator files..."

    download_file "${SCRIPT_PATH}/lib/common.sh" "${INSTALL_DIR}/lib/common.sh"
    download_file "${SCRIPT_PATH}/lib/pve.sh" "${INSTALL_DIR}/lib/pve.sh"
    download_file "${SCRIPT_PATH}/service.sh" "${INSTALL_DIR}/service.sh"
    download_file "${SCRIPT_PATH}/templates/config.yaml.example" "${INSTALL_DIR}/config.yaml.example"

    # Set permissions
    chmod +x "${INSTALL_DIR}/lib/common.sh"
    chmod +x "${INSTALL_DIR}/lib/pve.sh"
    chmod +x "${INSTALL_DIR}/service.sh"

    msg_ok "Files downloaded"
}

# Create systemd service
create_systemd() {
    msg_info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=PVE Orchestrator - VM and Container Startup Manager
Documentation=https://github.com/ftschopp/pve-scripts
After=network.target pve-cluster.service pveproxy.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/service.sh start
ExecStop=${INSTALL_DIR}/service.sh stop
RemainAfterExit=yes
TimeoutStartSec=600
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    msg_ok "Systemd service created"
}

# Copy config template if not exists
setup_config() {
    if [[ -f "${CONFIG_DIR}/config.yaml" ]]; then
        msg_warn "Configuration already exists: ${CONFIG_DIR}/config.yaml"
        msg_info "Your existing config is preserved"
    else
        cp "${INSTALL_DIR}/config.yaml.example" "${CONFIG_DIR}/config.yaml"
        msg_ok "Configuration template copied to: ${CONFIG_DIR}/config.yaml"
    fi
}

# Create convenience symlink
create_symlink() {
    rm -f /usr/local/bin/pve-orchestrator
    ln -s "${INSTALL_DIR}/service.sh" /usr/local/bin/pve-orchestrator
    msg_ok "Created symlink: /usr/local/bin/pve-orchestrator"
}

# Print post-install instructions
print_instructions() {
    echo ""
    echo -e "${GN}${BOLD}Installation Complete!${NC}"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo "1. Edit the configuration file:"
    echo -e "   ${YW}nano ${CONFIG_DIR}/config.yaml${NC}"
    echo ""
    echo "2. Test the orchestrator manually:"
    echo -e "   ${YW}pve-orchestrator status${NC}"
    echo -e "   ${YW}pve-orchestrator start${NC}"
    echo ""
    echo "3. Enable the service to start on boot:"
    echo -e "   ${YW}systemctl enable ${SERVICE_NAME}${NC}"
    echo ""
    echo "4. View logs:"
    echo -e "   ${YW}journalctl -u ${SERVICE_NAME} -f${NC}"
    echo -e "   ${YW}tail -f /var/log/pve-orchestrator.log${NC}"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  pve-orchestrator start   - Start all services"
    echo "  pve-orchestrator stop    - Stop all services"
    echo "  pve-orchestrator restart - Restart all services"
    echo "  pve-orchestrator status  - Show status"
    echo ""
}

# Uninstall function
uninstall() {
    msg_warn "Uninstalling PVE Orchestrator..."

    remove_service "${SERVICE_NAME}"
    rm -f /usr/local/bin/pve-orchestrator
    rm -rf "${INSTALL_DIR}"

    msg_ok "Uninstalled successfully"
    msg_info "Configuration preserved at: ${CONFIG_DIR}"
    msg_info "To remove config: rm -rf ${CONFIG_DIR}"
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
    check_proxmox

    install_yq
    create_directories
    download_files
    create_systemd
    setup_config
    create_symlink

    print_instructions
}

main "$@"
