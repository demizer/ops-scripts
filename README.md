# Operations Scripts

A collection of system administration and operational scripts for managing infrastructure, backups, and host configurations.

## Directory Structure

### `/archiso/`
Custom Arch Linux ISO creation and configuration scripts:
- `setup-archiso-env.sh` - Live ISO environment setup (SSH, NFS, email, tmux)
- `setup-custom-archiso.sh` - Builds custom Arch ISO with fish shell and tools
- `setup-sendmail-bridge.sh` - Configures sendmail for Proton Mail Bridge

### `/backup/`
Backup automation scripts:
- `rsync-backup.sh` - Rsync-based backup solution
- `tar-backup.sh` - Tar archive backup utility

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
- `LICENSE` - Project license

## Usage

Most scripts require root privileges and include built-in help and error handling. Scripts follow consistent color-coded output patterns for clear status reporting.

### Security Notes
- Scripts prompt for sensitive information rather than hardcoding credentials
- Configuration files use environment variables for secrets
- Container configs use standard development defaults (change for production)

## Prerequisites

Scripts are designed for Arch Linux but many utilities work across distributions. Common dependencies include:
- bash
- systemd
- standard Unix utilities (mount, rsync, tar, etc.)
