# PVE Scripts

A collection of remotely installable scripts for Proxmox VE, inspired by [Proxmox VE Helper Scripts](https://github.com/community-scripts/ProxmoxVE).

## Available Scripts

| Script | Description | Installation |
|--------|-------------|--------------|
| [orchestrator](scripts/orchestrator/) | Orchestrate VM, mount, and container startup order | [See below](#pve-orchestrator) |
| [disk-health](scripts/disk-health/) | Monitor HDD/SSD/NVMe health with SMART analysis | [See below](#disk-health-monitor) |

## Quick Installation

### PVE Orchestrator

Orchestrates the ordered startup of a TrueNAS VM, NFS/CIFS mount points, and LXC containers on Proxmox VE.

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"
```

Or with curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"
```

### Disk Health Monitor

Monitor the health of your HDDs, SSDs, and NVMe drives using SMART data with intuitive, colorful output.

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"
```

Or with curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"
```

**Commands:**
- `disk-health status` - Full status cards for all disks
- `disk-health summary` - Quick table summary
- `disk-health details -d /dev/sda` - Detailed info for one disk
- `disk-health check` - Check for critical issues
- `disk-health json` - JSON output for automation

## Repository Structure

```
pve-scripts/
├── misc/
│   └── build.func              # Shared functions for all installers
├── scripts/
│   ├── orchestrator/           # Orchestration script
│   │   ├── install.sh          # Remote installer
│   │   ├── service.sh          # Main service script
│   │   ├── lib/
│   │   │   ├── common.sh       # Common utility functions
│   │   │   └── pve.sh          # Proxmox VE specific functions
│   │   ├── templates/
│   │   │   └── config.yaml.example
│   │   └── README.md           # Script-specific documentation
│   └── disk-health/            # Disk health monitoring
│       ├── install.sh          # Remote installer
│       ├── service.sh          # Main script
│       ├── lib/
│       │   ├── common.sh       # Logging and display functions
│       │   └── smart.sh        # SMART data retrieval functions
│       └── README.md           # Script-specific documentation
└── README.md
```

## Adding a New Script

1. Create a folder under `scripts/your-script-name/`
2. Create an `install.sh` that sources `misc/build.func`
3. Implement your script-specific logic
4. Add a README.md for your script
5. Update this main README

### Example install.sh Template

```bash
#!/bin/bash
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/ftschopp/pve-scripts/main"
SCRIPT_PATH="scripts/your-script"

# Source shared build functions
source <(curl -fsSL "${REPO_RAW_URL}/misc/build.func") || \
source <(wget -qO- "${REPO_RAW_URL}/misc/build.func")

# Available functions from build.func:
# - msg_info, msg_warn, msg_error, msg_ok  (logging)
# - check_root, check_proxmox, check_debian (system checks)
# - download_file, source_url              (downloads)
# - install_yq, install_package            (dependencies)
# - create_systemd_service, remove_service (systemd)
# - print_header, print_success            (UI)

main() {
    check_root
    check_proxmox
    # Your installation logic here
}

main "$@"
```

### Directory Structure for New Scripts

```
scripts/your-script/
├── install.sh              # Installer (must source misc/build.func)
├── service.sh              # Main script (optional)
├── lib/                    # Script-specific libraries (optional)
├── templates/              # Configuration templates (optional)
└── README.md               # Documentation (required)
```

## Requirements

- Proxmox VE 7.x or 8.x
- Root access
- `wget` or `curl`

## License

MIT

## Contributing

1. Fork the repository
2. Create your feature branch
3. Add your script following the structure above
4. Submit a pull request
