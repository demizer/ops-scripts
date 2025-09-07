# Operations Scripts

A collection of system administration and operational scripts for managing infrastructure, backups, and host configurations.

## Configuring a New Host

Complete workflow for creating a new host configuration (reminder for future use):

### 1. Research Previous Host Setup

```bash
# Review git history to find the most recently created/updated host
git log --oneline --name-only | grep "hosts/" | head -20
```

### 2. Copy Existing Host Configuration

```bash
# Copy files from the most similar existing host
cp -r hosts/<existing-host> hosts/<new-host>
```

### 3. Update Device IDs

Use Claude to update all device identifiers in the new host files:
- Storage device paths (`/dev/disk/by-id/...`)
- Partition references
- Hardware-specific configurations

### 4. Customize Configuration

Review and update:
- Partition scheme in `01_partition.sh`
- Package installation list in `04_packages.sh`
- Any host-specific settings

### 5. Update Live ISO

```bash
# Copy updated scripts to live ISO environment
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdX --config-update
```

### 6. Boot and Setup Live Environment

1. Boot from the ISO
2. Connect to WiFi: `alvaone-wifi-setup`
3. Start tmux session: `alvaone-session`

### 7. Remote Installation (Optional)

For comfortable installation from another location:
```bash
# SSH into the live environment and run installation in tmux
ssh root@<live-ip>
tmux attach-session -t main
```

### 8. Install and Test

1. Run the full installation: `./archinstall.sh`
2. Boot into the new system
3. Test all functionality

### 9. Iterative Development

- Fix any boot issues using Claude
- Update scripts as needed
- May require multiple complete installations to perfect
- Test sanity checks and all system features
- It may take half a day and 10 full reinstalls to get everything right, but it's worth it because it won't need to be done again.

When changes are needed:
```bash
# From development machine, sync changes to live environment
TERM=xterm rsync -vrthP . root@192.168.5.128:/workspace/ --delete-after

# Test installation scripts
./archinstall.sh --mount --sanity  # or other specific steps
```

### 10. Finalize

```bash
# Commit all changes
git add hosts/<new-host>/
git commit -m "host: add new host <new-host>"
git push

# Update live ISO with final configuration
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdX --config-update

```

**IMPORTANT: REFLASH THE USB LIVE ENVIRONMENT WITH ANY UPDATES!!**

Keep it fresh so when it is used again in six months it can be redeployed to a new usb key and work.

Reflash and then boot into the live environment from the same system that was just configured and make sure the live environment still works!

### 11. Documentation Complete

The new host is ready for deployment and the live ISO contains the latest scripts.

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

- Auto-login as root with fish shell (no automatic tmux)
- Optional tmux session via `setup-session` command
- Custom MOTD with ASCII art branding
- Memory testing (memtest86+)
- Emergency boot options
- Session tools with pre-configured windows (ops-scripts, monitoring, network)

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

# Update configuration only (no partitioning/formatting)
sudo ./usb-tools/create-usb-tools.sh --device /dev/sdb --config-update
```

### Configuration Updates

The `--config-update` option allows updating existing USB tools systems without recreating them:

**What gets updated:**
- Shell configuration (fish shell setup)
- User configurations (neovim, fish config files)
- MOTD and branding
- Session tools (setup-session script)
- Environment variables
- ops-scripts repository in /workspace/

**What is preserved:**
- Partitioning and formatting
- Base system installation
- System services configuration
- SSH configuration
- Bootloader configuration

This is useful for applying script updates, configuration changes, or adding new ops-scripts without the time and risk of full system recreation.

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
