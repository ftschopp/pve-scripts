# PVE Orchestrator

Orchestrates the ordered startup and shutdown of VMs, NFS/CIFS mounts, and LXC containers on Proxmox VE.

## Features

- Start a TrueNAS (or any) VM and wait for it to be ready via health checks
- Mount NFS and CIFS shares after storage VM is available
- Start LXC containers in a specific order with configurable delays
- Support for mount dependencies (only start container if mount is available)
- Graceful shutdown in reverse order
- Systemd integration for boot-time orchestration
- YAML-based configuration

## Installation

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"
```

Or with curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)"
```

## Configuration

After installation, edit the configuration file:

```bash
nano /etc/pve-orchestrator/config.yaml
```

### Configuration Example

```yaml
# TrueNAS VM Configuration
truenas:
  vmid: 100
  wait_timeout: 300
  health_check:
    type: tcp          # tcp, ping, or http
    host: 192.168.1.10
    port: 22

# Mount Points (created after TrueNAS is ready)
mounts:
  - type: nfs
    source: "192.168.1.10:/mnt/pool/data"
    target: "/mnt/truenas/data"
    options: "rw,soft,intr"

  - type: nfs
    source: "192.168.1.10:/mnt/pool/media"
    target: "/mnt/truenas/media"

# LXC Containers (started in order)
containers:
  - ctid: 101
    name: "nginx-proxy"
    wait: 10                    # seconds before next container

  - ctid: 102
    name: "jellyfin"
    depends_on_mount: "/mnt/truenas/media"
    wait: 5

  - ctid: 103
    name: "nextcloud"
    depends_on_mount: "/mnt/truenas/data"

# Shutdown settings
shutdown:
  order: reverse
  container_timeout: 30
  vm_timeout: 120
  unmount_shares: true
```

### Configuration Options

#### TrueNAS VM

| Option | Description | Default |
|--------|-------------|---------|
| `vmid` | Proxmox VM ID | required |
| `wait_timeout` | Max seconds to wait for VM to be ready | 300 |
| `health_check.type` | Health check type: `tcp`, `ping`, or `http` | ping |
| `health_check.host` | IP or hostname to check | required |
| `health_check.port` | Port for TCP/HTTP checks | - |

#### Mounts

| Option | Description | Default |
|--------|-------------|---------|
| `type` | Mount type: `nfs` or `cifs` | required |
| `source` | Remote path (e.g., `192.168.1.10:/share`) | required |
| `target` | Local mount point | required |
| `options` | Mount options | nfs: `rw,soft,intr` |
| `credentials` | Path to CIFS credentials file | - |

#### Containers

| Option | Description | Default |
|--------|-------------|---------|
| `ctid` | Container ID | required |
| `name` | Container name (for logging) | container-{ctid} |
| `wait` | Seconds to wait after starting | 0 |
| `depends_on_mount` | Only start if this mount exists | - |

## Usage

### Commands

```bash
# Show status of all managed resources
pve-orchestrator status

# Start everything (VM -> mounts -> containers)
pve-orchestrator start

# Stop everything (containers -> unmount -> VM)
pve-orchestrator stop

# Restart all services
pve-orchestrator restart
```

### Systemd Service

```bash
# Enable auto-start on boot
systemctl enable pve-orchestrator

# Check service status
systemctl status pve-orchestrator

# View logs
journalctl -u pve-orchestrator -f

# View detailed logs
tail -f /var/log/pve-orchestrator.log
```

### Debug Mode

Enable verbose output:

```bash
DEBUG=1 pve-orchestrator start
```

## Startup Sequence

1. **Start TrueNAS VM** - Issues `qm start` and waits for VM to be running
2. **Health Check** - Waits for TrueNAS to respond (TCP/ping/HTTP)
3. **Mount Shares** - Mounts all configured NFS/CIFS shares
4. **Start Containers** - Starts each container in order, respecting:
   - `wait` delays between containers
   - `depends_on_mount` requirements

## Shutdown Sequence

1. **Stop Containers** - Gracefully stops containers in reverse order
2. **Unmount Shares** - Unmounts all managed mount points
3. **Stop TrueNAS VM** - Gracefully shuts down the VM

## File Locations

| Path | Description |
|------|-------------|
| `/opt/pve-orchestrator/` | Installation directory |
| `/etc/pve-orchestrator/config.yaml` | Configuration file |
| `/var/log/pve-orchestrator.log` | Log file |
| `/usr/local/bin/pve-orchestrator` | Command symlink |

## Uninstallation

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ftschopp/pve-scripts/main/scripts/orchestrator/install.sh)" -- --uninstall
```

This removes the script and service but preserves your configuration in `/etc/pve-orchestrator/`.

To completely remove:

```bash
rm -rf /etc/pve-orchestrator
```

## Troubleshooting

### VM doesn't start

- Check VM ID exists: `qm status <vmid>`
- Check Proxmox logs: `journalctl -u pve-cluster`

### Health check fails

- Verify network connectivity: `ping <host>`
- For TCP: `nc -zv <host> <port>`
- Increase `wait_timeout` if VM takes longer to boot

### Mounts fail

- Verify NFS server is exporting: `showmount -e <host>`
- Check NFS client is installed: `apt install nfs-common`
- For CIFS, check credentials file permissions (should be 600)

### Container doesn't start

- Check container exists: `pct status <ctid>`
- Check mount dependency is available
- Review logs: `tail /var/log/pve-orchestrator.log`

## License

MIT
