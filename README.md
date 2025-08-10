# Operations Scripts

A collection of system administration and operational scripts for managing infrastructure, backups, and host configurations.

## Quick Start - USB Tools System

### Complete USB Tools Workflow

Create a portable USB system with comprehensive tools for system administration:

```bash
# Complete workflow: create USB tools system and test
sudo ./usb-tools/test-usb-tools.sh --device /dev/sda

# Or with individual steps skipped
sudo ./usb-tools/test-usb-tools.sh --skip-test --device /dev/sda
```

### Manual Steps

To create a USB tools system manually:

```bash
# 1. Create the USB tools system
sudo ./usb-tools/create-usb-tools.sh --device /dev/sda

# 2. Test in QEMU (optional)
sudo ./usb-tools/test-usb-tools-qemu.sh --device /dev/sda
```

## Directory Structure

### `/usb-tools/`

USB-based portable system creation and testing scripts:

- `create-usb-tools.sh` - Creates bootable USB system using pacstrap with comprehensive tools
- `test-usb-tools.sh` - Complete automated workflow (create → test)
- `test-usb-tools-qemu.sh` - Tests USB system in QEMU with various boot options
- `setup-sendmail-bridge.sh` - Configures sendmail for Proton Mail Bridge

### `/backup/`

Backup automation scripts:

- `rsync-backup.sh` - Rsync-based backup solution
- `tar-backup.sh` - Tar archive backup utility with progress monitoring

### `/hosts/`

Host-specific configuration and setup scripts:

#### `/hosts/hammerhead/`

Storage and disk management scripts:

- `format.sh` - Disk formatting utilities
- `lvm.sh` - LVM configuration
- `mount.sh` - Mount point management
- `partition.sh` - Disk partitioning
- `raid.sh` - RAID setup and configuration
- `zap.sh` - Disk wiping utilities

#### `/hosts/jesusa-lt/`

- `setup.sh` - Laptop-specific setup script

#### `/hosts/ops/containers/`

Container orchestration configurations:

- `*.container` - Podman container definitions for Immich services
- `*.pod` - Pod specifications for grouped containers

### `/perf/`

Performance testing and monitoring:

- `pvt.sh` - Performance validation tools

### Root Level

- `packages.sh` - Package management utilities
- `lib.sh` - Common library functions
- `lib-loader.sh` - Library loading utilities
- `LICENSE` - Project license

## USB Tools System Features

The USB tools system created by `create-usb-tools.sh` includes:

### System Administration Tools

- Comprehensive network debugging (nmap, tcpdump, iperf3, mtr, traceroute)
- Disk recovery and forensics (ddrescue, testdisk, photorec, foremost)
- System monitoring (htop, iotop, lsof, strace)
- Hardware diagnostics (lshw, dmidecode, smartmontools)

### Development and Backup Tools

- Build tools (base-devel, git, neovim)
- Archive and compression utilities
- File synchronization (rsync, rclone)
- Self-reproduction capabilities (includes ops-scripts in /workspace/)

### Boot Features

- Auto-login as root with fish shell
- Tmux session management
- Custom MOTD with ASCII art branding
- Memory testing (memtest86+)
- Emergency boot options

## Usage

Most scripts require root privileges and include built-in help and error handling. Scripts follow consistent color-coded output patterns for clear status reporting.

### USB Tools System Creation

```bash
# Basic USB system creation
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdb

# With bridge password for email setup
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdb --bridge-password "mypassword"

# Force creation without confirmation
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdb --force
```

### Security Notes

- Scripts prompt for sensitive information rather than hardcoding credentials
- Configuration files use environment variables for secrets
- Container configs use standard development defaults (change for production)
- USB system includes SSH daemon with default password (change in production)

## Prerequisites

Scripts are designed for Arch Linux but many utilities work across distributions. Common dependencies include:

- bash
- systemd
- pacstrap (arch-install-scripts)
- standard Unix utilities (mount, rsync, tar, etc.)

For USB tools creation:

- Arch Linux host system
- Root privileges
- Target USB device with sufficient space (8GB minimum recommended)
