# Disk Health Monitor

Monitor the health of your HDDs, SSDs, and NVMe drives using SMART data with an intuitive, colorful output.

## Features

- **Visual Health Cards**: Beautiful ASCII cards showing disk status at a glance
- **Health Scoring**: Automatic health score (0-100%) based on critical SMART attributes
- **Multi-disk Support**: Works with HDDs, SSDs, and NVMe drives
- **Critical Warnings**: Immediate alerts for failing drives
- **JSON Output**: Machine-readable output for automation and monitoring
- **Detailed Analysis**: Deep dive into individual disk statistics

## Installation

### Quick Install (Recommended)

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"
```

Or using curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)"
```

### Uninstall

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/disk-health/install.sh)" -- --uninstall
```

## Usage

### Show Full Status (Default)

```bash
disk-health status
```

Displays detailed health cards for all disks with:
- Device name, type (HDD/SSD/NVMe), and health score
- Model and serial number
- Temperature, power-on time, and capacity
- SMART status and type-specific metrics
- Critical warnings if any issues detected

### Quick Summary

```bash
disk-health summary
```

Shows a compact table view of all disks - perfect for quick checks.

### Detailed Information

```bash
disk-health details -d /dev/sda
```

Deep dive into a specific disk showing:
- Complete device information
- All health metrics
- Usage statistics
- SMART self-test history
- Detailed warnings and recommendations

### Health Check

```bash
disk-health check
```

Quick pass/fail check for all disks. Returns exit code 1 if any issues found - useful for scripts and monitoring.

### JSON Output

```bash
disk-health json
```

Machine-readable JSON output for integration with monitoring systems like Prometheus, Grafana, or custom scripts.

## Health Score Calculation

The health score (0-100%) is calculated based on:

| Factor | Impact |
|--------|--------|
| SMART Health Status Failed | -50% |
| Reallocated Sectors > 100 | -30% |
| Reallocated Sectors > 10 | -15% |
| Pending Sectors > 0 | -10% |
| Uncorrectable Sectors > 0 | -15% |
| SMART Errors > 10 | -20% |
| SMART Errors > 0 | -5% |
| SSD Life < 10% | -30% |
| SSD Life < 30% | -15% |
| Temperature > 60°C | -15% |
| Temperature > 50°C | -5% |

### Health Status Levels

| Score | Status | Description |
|-------|--------|-------------|
| 90-100% | Excellent | Disk is in perfect condition |
| 70-89% | Good | Disk is healthy with minor wear |
| 50-69% | Fair | Some degradation, monitor closely |
| 30-49% | Poor | Significant issues, plan replacement |
| 0-29% | Critical | Immediate replacement recommended |

## Output Examples

### Status Card
```
┌─────────────────────────────────────────────────────────────────┐
│ sda          │ SSD                  │ Excellent  │ Score:  98% │
├─────────────────────────────────────────────────────────────────┤
│  Model:  Samsung SSD 870 EVO 1TB                                │
│  Serial: S5XXNJ0R123456                                         │
├─────────────────────────────────────────────────────────────────┤
│  Size: 931 GB          Temp: 32°C       Power On: 1y 45d       │
│  SMART Status: PASSED                                           │
│  Life Remaining: 98%        Total Written: 12 TB               │
└─────────────────────────────────────────────────────────────────┘
```

### Summary Table
```
DEVICE       TYPE     MODEL                     SIZE       TEMP     HEALTH
────────────────────────────────────────────────────────────────────────────
sda          SSD      Samsung SSD 870 EVO       931 GB     32°C     Excellent (98%)
sdb          HDD      WDC WD40EFRX-68N32N0      3.6 TB     35°C     Good (85%)
nvme0n1      NVMe     Samsung SSD 980 PRO       465 GB     42°C     Excellent (100%)
```

## Requirements

- Linux (Debian/Ubuntu-based or Proxmox VE)
- Root access
- `smartmontools` package (auto-installed)

## Logs

View operation logs:

```bash
tail -f /var/log/disk-health.log
```

## Integration Examples

### Cron Job for Daily Check

```bash
# Add to /etc/crontab or crontab -e
0 6 * * * root /usr/local/bin/disk-health check || echo "Disk issues detected" | mail -s "Disk Alert" admin@example.com
```

### Prometheus/Node Exporter

```bash
# Generate metrics file
disk-health json > /var/lib/node_exporter/disk-health.json
```

### Monitoring Script

```bash
#!/bin/bash
if ! disk-health check -q; then
    # Send alert via your preferred method
    curl -X POST "https://alerts.example.com/webhook" \
        -H "Content-Type: application/json" \
        -d "$(disk-health json)"
fi
```

## Files

| Path | Description |
|------|-------------|
| `/opt/disk-health/` | Installation directory |
| `/opt/disk-health/service.sh` | Main script |
| `/opt/disk-health/lib/common.sh` | Common functions |
| `/opt/disk-health/lib/smart.sh` | SMART data functions |
| `/usr/local/bin/disk-health` | Command symlink |
| `/var/log/disk-health.log` | Log file |

## Troubleshooting

### "No disks found"

Ensure you're running as root and have block devices available:
```bash
lsblk -d
```

### "SMART not supported"

Some virtual disks or RAID controllers don't expose SMART data. Check if the disk supports SMART:
```bash
smartctl -i /dev/sda
```

### Temperature shows "N/A"

Some SSDs don't report temperature via SMART. This is normal for certain models.

## License

MIT License - See repository for details.
