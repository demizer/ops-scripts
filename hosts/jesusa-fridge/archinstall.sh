#!/bin/bash

# Arch Linux installer for jesusa-fridge
# Sets up a complete Arch Linux system using partition.sh, format.sh, mount.sh, and packages.sh

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    err "This script must be run as root"
fi

# Check if running on Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    err "This script must be run on Arch Linux"
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7L9NJ0Y438532K"
MOUNT_ROOT="/mnt/root"
HOSTNAME="jesusa-fridge"

# Setup logging
LOG_FILE="archinstall-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install Arch Linux on jesusa-fridge system

OPTIONS:
    -h, --help              Show this help message
    --help-long             Show detailed descriptions of each step
    -f, --force             Skip confirmation prompts

STEP OPTIONS (run individual or multiple steps):
    --partition             Run partitioning step
    --format                Run formatting step
    --mount                 Run mounting step
    --base-system           Run base system installation
    --configure             Run system configuration
    --bootloader            Run bootloader setup
    --initramfs             Run initramfs generation
    --configure-pacman      Run pacman configuration and repository setup
    --packages              Run package installation
    --nvidia                Run NVIDIA modules configuration
    --groups                Run group configuration
    --users                 Run user configuration
    --sanity                Run boot readiness verification

    Note: Multiple steps can be combined and will run in correct logical order

    --steps-from STEP       Run from specified step to end

EXAMPLES:
    $0                                          # Full installation
    $0 --force                                  # Full installation, skip prompts

    # Single steps:
    $0 --partition                              # Only partition device
    $0 --configure-pacman                       # Only configure pacman.conf

    # Multiple steps (run in logical order regardless of command line order):
    $0 --format --mount                         # Format then mount
    $0 --nvidia --groups --users               # Configure NVIDIA, then groups, then users
    $0 --packages --nvidia                     # Install packages then configure NVIDIA

    # Range of steps:
    $0 --steps-from configure-pacman            # Run from pacman config to end

EOF
}

show_help_long() {
    cat << EOF
Usage: $0 [OPTIONS]

Install Arch Linux on jesusa-fridge system

OPTIONS:
    -h, --help              Show this help message
    --help-long             Show detailed descriptions of each step
    -f, --force             Skip confirmation prompts

STEP OPTIONS (run individual or multiple steps):

DETAILED STEP DESCRIPTIONS:

1. --partition
   Creates partition table on Samsung NVMe SSD with:
   - 512MB EFI System Partition (FAT32)
   - Remaining space as root partition (ext4)
   Uses partition.sh script with GPT partitioning scheme

2. --format
   Formats the created partitions:
   - EFI partition: FAT32 filesystem with proper labels
   - Root partition: ext4 filesystem with optimal settings
   Uses format.sh script with filesystem verification

3. --mount
   Mounts partitions to /mnt/root for installation:
   - Root partition mounted at /mnt/root
   - EFI partition mounted at /mnt/root/boot
   Uses mount.sh script with proper mount options

4. --base-system
   Installs essential Arch Linux base system using pacstrap:
   - base, linux-zen kernel, linux-firmware
   - Development tools: base-devel, git, neovim
   - Network: networkmanager, openssh
   - Boot: grub, efibootmgr
   - Shell: fish, sudo

5. --configure
   Configures the basic system settings:
   - Generates fstab with NFS mounts for repositories
   - Sets hostname to jesusa-fridge
   - Configures locale (en_US.UTF-8) and timezone (LA)
   - Sets root password interactively
   - Configures sudo for wheel group
   - Enables NetworkManager and sshd services
   - Configures SSH security (no root login)

6. --bootloader
   Installs and configures GRUB bootloader:
   - Installs GRUB for UEFI systems
   - Adds NVIDIA kernel parameters (nvidia-drm.modeset=1)
   - Generates GRUB configuration with linux-zen as default

7. --initramfs
   Generates initial RAM filesystem:
   - Creates initramfs for linux-zen kernel
   - Initial generation without NVIDIA modules
   - Provides early boot environment

8. --configure-pacman
   Customizes package manager configuration:
   - Sets custom cache directory (/mnt/arch_pkg_cache)
   - Enables VerbosePkgLists for detailed package info
   - Enables multilib repository for 32-bit support
   - Configures alvaone custom repository if available
   - Sets up NFS systemd mount units

9. --packages
   Installs comprehensive package set (200+ packages):
   - Development: docker, python, rust, go
   - Desktop: gnome, gdm, chromium, firefox
   - Media: vlc, obs-studio, gimp, krita
   - Professional: datagrip, pycharm, rustrover
   - System utilities and development tools
   Enables GDM for graphical login

10. --nvidia
    Configures NVIDIA graphics support:
    - Adds NVIDIA modules to mkinitcpio.conf
    - Regenerates initramfs with NVIDIA drivers
    - Configures proper module loading order

11. --groups
    Sets up user groups and NFS directories:
    - Creates bigdata group (GID 5000)
    - Creates NFS mount directories
    - Sets proper permissions for shared access

12. --users
    Creates and configures jesusa user:
    - Creates user with host system UID/GID/groups
    - Sets interactive password
    - Configures fish shell and sudo access
    - Maintains host system compatibility

13. --sanity
    Verifies system boot readiness:
    - Checks EFI boot manager for GRUB entry
    - Verifies GDM service is enabled
    - Validates GRUB config contains linux-zen
    - Confirms fstab entries are correct
    - Checks initramfs and kernel files exist
    - Verifies essential services and user config
    - Tests NVIDIA module configuration

    --steps-from STEP       Run from specified step to end

EXAMPLES:
    $0                                          # Full installation
    $0 --force                                  # Full installation, skip prompts

    # Single steps:
    $0 --partition                              # Only partition device
    $0 --configure-pacman                       # Only configure pacman.conf

    # Multiple steps (run in logical order regardless of command line order):
    $0 --format --mount                         # Format then mount
    $0 --nvidia --groups --users               # Configure NVIDIA, then groups, then users
    $0 --packages --nvidia                     # Install packages then configure NVIDIA

    # Range of steps:
    $0 --steps-from configure-pacman            # Run from pacman config to end

EOF
}

# Parse command line arguments
FORCE=false
STEPS_FROM=""

# Step flags
STEP_PARTITION=false
STEP_FORMAT=false
STEP_MOUNT=false
STEP_BASE_SYSTEM=false
STEP_CONFIGURE=false
STEP_BOOTLOADER=false
STEP_INITRAMFS=false
STEP_CONFIGURE_PACMAN=false
STEP_PACKAGES=false
STEP_NVIDIA=false
STEP_GROUPS=false
STEP_USERS=false
STEP_SANITY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        --help-long)
            show_help_long
            exit 0
            ;;
        -f | --force)
            FORCE=true
            shift
            ;;
        --partition)
            STEP_PARTITION=true
            shift
            ;;
        --format)
            STEP_FORMAT=true
            shift
            ;;
        --mount)
            STEP_MOUNT=true
            shift
            ;;
        --base-system)
            STEP_BASE_SYSTEM=true
            shift
            ;;
        --configure)
            STEP_CONFIGURE=true
            shift
            ;;
        --bootloader)
            STEP_BOOTLOADER=true
            shift
            ;;
        --initramfs)
            STEP_INITRAMFS=true
            shift
            ;;
        --configure-pacman)
            STEP_CONFIGURE_PACMAN=true
            shift
            ;;
        --packages)
            STEP_PACKAGES=true
            shift
            ;;
        --nvidia)
            STEP_NVIDIA=true
            shift
            ;;
        --groups)
            STEP_GROUPS=true
            shift
            ;;
        --users)
            STEP_USERS=true
            STEP_SANITY=true
            shift
            ;;
        --sanity)
            STEP_SANITY=true
            shift
            ;;
        --steps-from)
            if [[ -z "$2" ]]; then
                err "--steps-from requires a step name"
            fi
            STEPS_FROM="$2"
            shift 2
            ;;
        *)
            err "Unknown option: $1"
            ;;
    esac
done

# Handle --steps-from flag
if [[ -n "$STEPS_FROM" ]]; then
    case "$STEPS_FROM" in
        partition)
            STEP_PARTITION=true
            STEP_FORMAT=true
            STEP_MOUNT=true
            STEP_BASE_SYSTEM=true
            STEP_CONFIGURE=true
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        format)
            STEP_FORMAT=true
            STEP_MOUNT=true
            STEP_BASE_SYSTEM=true
            STEP_CONFIGURE=true
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        mount)
            STEP_MOUNT=true
            STEP_BASE_SYSTEM=true
            STEP_CONFIGURE=true
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        base-system)
            STEP_BASE_SYSTEM=true
            STEP_CONFIGURE=true
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        configure)
            STEP_CONFIGURE=true
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        bootloader)
            STEP_BOOTLOADER=true
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        initramfs)
            STEP_INITRAMFS=true
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        configure-pacman)
            STEP_CONFIGURE_PACMAN=true
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        packages)
            STEP_PACKAGES=true
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        nvidia)
            STEP_NVIDIA=true
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        groups)
            STEP_GROUPS=true
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        users)
            STEP_USERS=true
            STEP_SANITY=true
            ;;
        sanity)
            STEP_SANITY=true
            ;;
        *)
            err "Invalid step name: $STEPS_FROM"
            ;;
    esac
fi

# Setup alvaone repository first
setup_alvaone_repo() {
    msg "Setting up alvaone repository..."

    local setup_script="$SCRIPT_DIR/../../usb-tools/setup-alvaone-repo.sh"
    if [[ -f "$setup_script" ]]; then
        "$setup_script" || {
            warn "Failed to setup alvaone repository - continuing with standard repositories"
        }
    else
        warn "Alvaone repository setup script not found - continuing with standard repositories"
    fi
}

msg "Arch Linux installer for jesusa-fridge"
msg "All output is being logged to: $PWD/$LOG_FILE"

# Check if any step flags are set
ANY_STEP_FLAG=false
for flag in "$STEP_PARTITION" "$STEP_FORMAT" "$STEP_MOUNT" "$STEP_BASE_SYSTEM" "$STEP_CONFIGURE" "$STEP_BOOTLOADER" "$STEP_INITRAMFS" "$STEP_CONFIGURE_PACMAN" "$STEP_PACKAGES" "$STEP_NVIDIA" "$STEP_GROUPS" "$STEP_USERS" "$STEP_SANITY"; do
    if [[ "$flag" == true ]]; then
        ANY_STEP_FLAG=true
        break
    fi
done

# Only run setup and confirmations for full installation
if [[ "$ANY_STEP_FLAG" != true ]]; then
    # Setup alvaone repository at the very beginning
    setup_alvaone_repo

    # Show device information
    msg "Target device: $DEVICE"
    lsblk "$DEVICE" 2> /dev/null | sed 's/^/    /' || {
        err "Failed to read device information"
    }

    # Confirmation unless --force
    if [[ "$FORCE" != true ]]; then
        echo
        warn "This will completely destroy all data on $DEVICE!"
        read -p "Are you sure you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            msg "Operation cancelled"
            exit 0
        fi
    fi
fi

# Function to ask user about unmounting (on any exit)
ask_unmount_on_exit() {
    local exit_code=$?
    if mountpoint -q "$MOUNT_ROOT" 2> /dev/null; then
        echo
        if [[ $exit_code -ne 0 ]]; then
            warn "Installation failed. The filesystem is still mounted for debugging."
        fi
        read -p "Do you want to unmount $MOUNT_ROOT? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            msg "Unmounting $MOUNT_ROOT"
            umount -R "$MOUNT_ROOT" 2> /dev/null
            msg "Unmounted successfully"
        else
            msg "Leaving $MOUNT_ROOT mounted"
        fi
    fi
}

# Function to ask user about unmounting at the end of successful installation
ask_unmount() {
    if mountpoint -q "$MOUNT_ROOT" 2> /dev/null; then
        echo
        read -p "Do you want to unmount $MOUNT_ROOT? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            msg "Unmounting $MOUNT_ROOT"
            umount -R "$MOUNT_ROOT" 2> /dev/null
            msg "Unmounted successfully"
        else
            msg "Leaving $MOUNT_ROOT mounted"
        fi
    fi
}

# Signal handling for immediate cleanup
cleanup_on_signal() {
    local signal=$1
    msg "Received signal $signal - cleaning up and exiting..."

    # Clean up any bind mounts that might still be active
    if mountpoint -q "$MOUNT_ROOT/mnt/arch_repo" 2> /dev/null; then
        umount "$MOUNT_ROOT/mnt/arch_repo" 2> /dev/null || true
    fi
    if mountpoint -q "$MOUNT_ROOT/mnt/arch_pkg_cache" 2> /dev/null; then
        umount "$MOUNT_ROOT/mnt/arch_pkg_cache" 2> /dev/null || true
    fi

    # Call the normal exit handler
    ask_unmount_on_exit
    exit 130 # Standard exit code for Ctrl+C
}

# Set up signal traps for immediate response
trap 'cleanup_on_signal SIGINT' INT
trap 'cleanup_on_signal SIGTERM' TERM
trap ask_unmount_on_exit EXIT

# Step 4: Install base system with pacstrap
install_base_system() {
    msg "Installing base system with pacstrap..."

    # Check if pacstrap is available
    if ! command -v pacstrap &> /dev/null; then
        err "pacstrap not found. Please install arch-install-scripts"
    fi

    # Verify mount point exists and is properly mounted
    if [[ ! -d "$MOUNT_ROOT" ]]; then
        err "Mount root directory $MOUNT_ROOT does not exist"
    fi

    if ! mountpoint -q "$MOUNT_ROOT"; then
        err "$MOUNT_ROOT is not mounted"
    fi

    # Base packages for a minimal but functional system
    local base_packages=(
        base
        linux-zen
        linux-zen-headers
        linux-firmware
        base-devel
        grub
        efibootmgr
        networkmanager
        sudo
        fish
        neovim
        git
        openssh
    )

    # Debug: Check mount point and available space before pacstrap
    msg "Mount point status before pacstrap:"
    msg "Directory exists: $(test -d "$MOUNT_ROOT" && echo "YES" || echo "NO")"
    msg "Mount status: $(mountpoint -q "$MOUNT_ROOT" && echo "MOUNTED" || echo "NOT MOUNTED")"
    msg "Available space:"
    df -h "$MOUNT_ROOT" || true
    msg "Mount point contents:"
    ls -la "$MOUNT_ROOT" || true
    msg "Active mounts:"
    mount | grep "$MOUNT_ROOT" || true

    # Run pacstrap to install base packages with verbose output
    msg "Running pacstrap with packages: ${base_packages[*]}"
    msg "Command: pacstrap -c '$MOUNT_ROOT' --noconfirm ${base_packages[*]}"

    # Run pacstrap and capture both stdout and stderr
    if ! pacstrap -c "$MOUNT_ROOT" --noconfirm "${base_packages[@]}" 2>&1 | tee /tmp/pacstrap.log; then
        err "Failed to install base system"
        msg "pacstrap exit code: ${PIPESTATUS[0]}"
        msg "pacstrap output (last 20 lines):"
        tail -20 /tmp/pacstrap.log || true
        msg "Mount point contents after failed pacstrap:"
        ls -la "$MOUNT_ROOT" || true
        msg "Filesystem status after failure:"
        df -h "$MOUNT_ROOT" || true
        return 1
    fi

    # Verify base system was actually installed
    msg "Verifying base system installation..."
    missing_dirs=()
    for dir in etc usr bin sbin lib; do
        if [[ ! -d "$MOUNT_ROOT/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        err "Base system installation incomplete - missing directories: ${missing_dirs[*]}"
        msg "Mount point contents after pacstrap:"
        ls -la "$MOUNT_ROOT" || true
        msg "Checking what was actually installed:"
        find "$MOUNT_ROOT" -maxdepth 2 -type d | head -20 || true
        return 1
    fi

    # Additional verification: check for key files
    key_files=("/etc/pacman.conf" "/usr/bin/bash" "/bin/sh")
    missing_files=()
    for file in "${key_files[@]}"; do
        if [[ ! -e "$MOUNT_ROOT$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        warn "Some expected files missing: ${missing_files[*]}"
        msg "This may indicate an incomplete installation"
    fi

    # Sync after package installation
    sync
    msg "Base system installed successfully"
    msg "Installation summary:"
    msg "  Root filesystem size: $(du -sh "$MOUNT_ROOT" 2> /dev/null | cut -f1 || echo "unknown")"
    msg "  Key directories present: $(ls -d "$MOUNT_ROOT"/{etc,usr,bin,sbin,lib} 2> /dev/null | wc -l || echo "0")/5"
}

# Step 5: Configure the system
configure_system() {
    msg "Configuring system..."

    # Generate fstab with header comments
    cat > "$MOUNT_ROOT/etc/fstab" << 'EOF'
# Static information about the filesystems.
# See fstab(5) for details.

# <file system> <dir> <type> <options> <dump> <pass>
EOF

    # Generate fstab entries and append
    genfstab -U "$MOUNT_ROOT" >> "$MOUNT_ROOT/etc/fstab" || {
        err "Failed to generate fstab"
        return 1
    }

    # Add additional NFS mounts
    cat >> "$MOUNT_ROOT/etc/fstab" << 'EOF'

# NFS mounts for alvaone repository and backups
nas.alvaone.net:/mnt/bigdata/arch_repo/alvaone_repo     /mnt/arch_repo          nfs4    _netdev,noauto,noatime,nodiratime,rsize=131072,wsize=131072,x-systemd.automount,x-systemd.after=network-online.target,x-systemd.mount-timeout=30,timeo=600,x-systemd.idle-timeout=1min 0 0
nas.alvaone.net:/mnt/bigdata/arch_repo/pac_cache        /mnt/arch_pkg_cache     nfs4    _netdev,noauto,noatime,nodiratime,rsize=131072,wsize=131072,x-systemd.automount,x-systemd.after=network-online.target,x-systemd.mount-timeout=30,timeo=600,x-systemd.idle-timeout=1min 0 0
nas.alvaone.net:/mnt/bigdata/backups                    /mnt/backups            nfs4    _netdev,noauto,noatime,nodiratime,rsize=131072,wsize=131072,x-systemd.automount,x-systemd.after=network-online.target,x-systemd.mount-timeout=30,timeo=600,x-systemd.idle-timeout=1min 0 0
EOF

    # Set hostname
    echo "$HOSTNAME" > "$MOUNT_ROOT/etc/hostname"

    # Configure locale
    echo "en_US.UTF-8 UTF-8" > "$MOUNT_ROOT/etc/locale.gen"
    echo "LANG=en_US.UTF-8" > "$MOUNT_ROOT/etc/locale.conf"

    # Set timezone
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime || {
        err "Failed to set timezone"
        return 1
    }

    # Generate locale
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" locale-gen || {
        err "Failed to generate locales"
        return 1
    }

    # Set root password interactively
    msg "Setting root password..."
    msg "You will be prompted to enter a password for the root user"
    arch-chroot "$MOUNT_ROOT" passwd root || {
        err "Failed to set root password"
        return 1
    }

    # Configure sudo
    echo "%wheel ALL=(ALL:ALL) ALL" >> "$MOUNT_ROOT/etc/sudoers"

    # Enable essential services
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" systemctl enable NetworkManager || {
        err "Failed to enable NetworkManager"
        return 1
    }
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" systemctl enable sshd || {
        err "Failed to enable sshd"
        return 1
    }

    # Configure SSH to disable root login
    msg "Configuring SSH security settings..."
    echo "PermitRootLogin no" >> "$MOUNT_ROOT/etc/ssh/sshd_config"
    echo "PasswordAuthentication yes" >> "$MOUNT_ROOT/etc/ssh/sshd_config"
    echo "PubkeyAuthentication yes" >> "$MOUNT_ROOT/etc/ssh/sshd_config"

    # Configure hostname resolution
    cat > "$MOUNT_ROOT/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   jesusa-fridge.alvaone.net jesusa-fridge
EOF

    msg "System configured successfully"
}

# Step 6: Install and configure bootloader
setup_bootloader() {
    msg "Setting up GRUB bootloader..."

    # Install GRUB to EFI partition
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || {
        err "Failed to install GRUB"
        return 1
    }

    # Add NVIDIA kernel parameters to GRUB
    msg "Configuring NVIDIA kernel parameters in GRUB..."
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' "$MOUNT_ROOT/etc/default/grub" || {
        err "Failed to configure NVIDIA kernel parameters"
        return 1
    }

    # Generate GRUB configuration
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" grub-mkconfig -o /boot/grub/grub.cfg || {
        err "Failed to generate GRUB configuration"
        return 1
    }

    msg "Bootloader configured successfully"
}

# Step 7: Generate initramfs
generate_initramfs() {
    msg "Generating initramfs..."

    # Generate initramfs (without NVIDIA modules initially)
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" mkinitcpio -P || {
        err "Failed to generate initramfs"
        return 1
    }

    # Sync after initramfs generation
    sync
    msg "Initramfs generated successfully"
}

# Step 8: Configure pacman and setup repositories
setup_pacman_and_repos() {
    msg "Configuring pacman and setting up repositories..."

    # Customize pacman.conf with CacheDir and other settings
    msg "Customizing pacman.conf..."
    if [[ -f "$MOUNT_ROOT/etc/pacman.conf" ]]; then
        # Update CacheDir setting
        sed -i 's|^#CacheDir.*|CacheDir    = /mnt/arch_pkg_cache/ # trailing slash required|' "$MOUNT_ROOT/etc/pacman.conf"

        # Uncomment VerbosePkgLists
        sed -i 's|^#VerbosePkgLists|VerbosePkgLists|' "$MOUNT_ROOT/etc/pacman.conf"

        # Uncomment multilib repository
        sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' "$MOUNT_ROOT/etc/pacman.conf"

        msg "Updated CacheDir, VerbosePkgLists, and enabled multilib repository in pacman.conf"
    fi

    # Copy alvaone repo setup if the host has it configured
    if [[ -f /etc/pacman.d/alvaone ]]; then
        cp /etc/pacman.d/alvaone "$MOUNT_ROOT/etc/pacman.d/"

        # Update pacman.conf in new system to include alvaone repo
        if ! grep -q "Include.*alvaone" "$MOUNT_ROOT/etc/pacman.conf"; then
            echo "" >> "$MOUNT_ROOT/etc/pacman.conf"
            echo "Include = /etc/pacman.d/alvaone" >> "$MOUNT_ROOT/etc/pacman.conf"
            msg "Added alvaone repository to new system"
        fi
    fi

    # Copy NFS mount configuration for alvaone repo
    if mountpoint -q /mnt/arch_repo 2> /dev/null && mountpoint -q /mnt/arch_pkg_cache 2> /dev/null; then
        # Create systemd mount units for the new system
        mkdir -p "$MOUNT_ROOT/etc/systemd/system"

        # Alvaone repo mount
        cat > "$MOUNT_ROOT/etc/systemd/system/mnt-arch_repo.mount" << 'EOF'
[Unit]
Description=Alvaone Repository NFS Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=nas.alvaone.net:/mnt/bigdata/arch_repo/alvaone_repo
Where=/mnt/arch_repo
Type=nfs
Options=_netdev,noauto,noatime,nodiratime,rsize=131072,wsize=131072,timeo=600

[Install]
WantedBy=multi-user.target
EOF

        # Package cache mount
        cat > "$MOUNT_ROOT/etc/systemd/system/mnt-arch_pkg_cache.mount" << 'EOF'
[Unit]
Description=Package Cache NFS Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=nas.alvaone.net:/mnt/bigdata/arch_repo/pac_cache
Where=/mnt/arch_pkg_cache
Type=nfs
Options=_netdev,noauto,noatime,nodiratime,rsize=131072,wsize=131072,timeo=600

[Install]
WantedBy=multi-user.target
EOF

        # Enable the mounts
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" systemctl enable mnt-arch_repo.mount || {
            err "Failed to enable mnt-arch_repo.mount"
            return 1
        }
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" systemctl enable mnt-arch_pkg_cache.mount || {
            err "Failed to enable mnt-arch_pkg_cache.mount"
            return 1
        }

        msg "Configured NFS mounts for new system"
    fi
}

# Helper function to setup repository bind mounts
setup_repository_bind_mounts() {
    # Create directories for bind mounts and set up alvaone repository access
    msg "Setting up repository bind mounts in chroot..."
    mkdir -p "$MOUNT_ROOT/mnt/arch_repo" "$MOUNT_ROOT/mnt/arch_pkg_cache" || {
        err "Failed to create repository mount directories in chroot"
        return 1
    }

    # Bind mount alvaone repository and package cache from host if available
    if mountpoint -q /mnt/arch_repo 2> /dev/null; then
        if ! mountpoint -q "$MOUNT_ROOT/mnt/arch_repo" 2> /dev/null; then
            msg "Bind mounting alvaone repository..."
            mount --bind /mnt/arch_repo "$MOUNT_ROOT/mnt/arch_repo" || {
                err "Failed to bind mount alvaone repository"
                return 1
            }
        fi
    else
        warn "Host alvaone repository not mounted - packages.sh may fail"
    fi

    if mountpoint -q /mnt/arch_pkg_cache 2> /dev/null; then
        if ! mountpoint -q "$MOUNT_ROOT/mnt/arch_pkg_cache" 2> /dev/null; then
            msg "Bind mounting package cache..."
            mount --bind /mnt/arch_pkg_cache "$MOUNT_ROOT/mnt/arch_pkg_cache" || {
                err "Failed to bind mount package cache"
                return 1
            }
        fi
    else
        warn "Host package cache not mounted - packages.sh may be slower"
    fi
}

# Helper function to cleanup repository bind mounts
cleanup_repository_bind_mounts() {
    msg "Cleaning up bind mounts..."
    if mountpoint -q "$MOUNT_ROOT/mnt/arch_repo" 2> /dev/null; then
        umount "$MOUNT_ROOT/mnt/arch_repo" || warn "Failed to unmount alvaone repository bind mount"
    fi
    if mountpoint -q "$MOUNT_ROOT/mnt/arch_pkg_cache" 2> /dev/null; then
        umount "$MOUNT_ROOT/mnt/arch_pkg_cache" || warn "Failed to unmount package cache bind mount"
    fi
}

# Step 9: Install additional packages
install_packages() {
    msg "Installing additional packages..."

    # Check if packages.sh exists
    if [[ ! -f "$SCRIPT_DIR/packages.sh" ]]; then
        err "packages.sh not found at $SCRIPT_DIR/packages.sh"
    fi

    # Debug: Show what we're working with
    msg "Source: $SCRIPT_DIR/packages.sh"
    msg "Mount point: $MOUNT_ROOT"
    msg "Target: $MOUNT_ROOT/root/"

    # Ensure the /root directory exists in chroot
    mkdir -p "$MOUNT_ROOT/root" || {
        err "Failed to create /root directory in chroot"
    }

    # Setup repository bind mounts
    setup_repository_bind_mounts || return 1

    # Copy packages.sh to the new system and run it in chroot
    cp "$SCRIPT_DIR/packages.sh" "$MOUNT_ROOT/root/" || {
        err "Failed to copy packages.sh to chroot environment"
    }
    chmod +x "$MOUNT_ROOT/root/packages.sh"

    # Verify the file was copied successfully
    if [[ ! -f "$MOUNT_ROOT/root/packages.sh" ]]; then
        err "packages.sh was not successfully copied to $MOUNT_ROOT/root/"
    fi

    msg "Successfully copied packages.sh to chroot environment"

    # Run packages installation in chroot with better signal handling
    msg "Running packages installation..."
    msg "Note: This may take a while. Press Ctrl+C to cancel if needed."

    # Use a more direct approach that handles signals better
    if ! arch-chroot "$MOUNT_ROOT" /root/packages.sh --force; then
        # Clean up bind mounts even on failure
        msg "Package installation failed - cleaning up bind mounts..."
        cleanup_repository_bind_mounts
        err "Package installation failed"
    fi

    # Clean up
    rm -f "$MOUNT_ROOT/root/packages.sh"

    # Only unmount bind mounts if this is not part of a multi-step run
    # If ANY_STEP_FLAG is false, we're doing a full install and should cleanup
    # If ANY_STEP_FLAG is true and only STEP_PACKAGES is true, we should cleanup
    if [[ "$ANY_STEP_FLAG" == false ]] || [[ "$STEP_PACKAGES" == true && "$STEP_NVIDIA" != true && "$STEP_GROUPS" != true && "$STEP_USERS" != true ]]; then
        cleanup_repository_bind_mounts
    else
        msg "Keeping bind mounts for subsequent steps"
    fi

    # Enable gdm service now that it's installed
    msg "Enabling gdm service..."
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" systemctl enable gdm || {
        err "Failed to enable gdm"
        return 1
    }

    msg "Package installation completed"
}

# Step 9.5: Configure NVIDIA modules (after packages are installed)
configure_nvidia_modules() {
    msg "Configuring NVIDIA modules in mkinitcpio.conf..."

    # Configure NVIDIA modules in mkinitcpio.conf after packages are installed
    sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MOUNT_ROOT/etc/mkinitcpio.conf" || {
        err "Failed to configure NVIDIA modules in mkinitcpio.conf"
        return 1
    }

    # Regenerate initramfs with NVIDIA modules
    msg "Regenerating initramfs with NVIDIA modules..."
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" mkinitcpio -P || {
        err "Failed to regenerate initramfs with NVIDIA modules"
        return 1
    }

    msg "NVIDIA modules configuration completed"
}

# Step 10: Configure groups
configure_groups() {
    msg "Configuring groups..."

    # Check if groups.sh exists
    if [[ ! -f "$SCRIPT_DIR/groups.sh" ]]; then
        err "groups.sh not found at $SCRIPT_DIR/groups.sh"
        return 1
    fi

    # Run groups configuration
    "$SCRIPT_DIR/groups.sh" -m "$MOUNT_ROOT" || {
        err "Group configuration failed"
        return 1
    }

    # Create and configure bigdata NFS directories
    msg "Creating bigdata NFS mount directories..."
    for dir in /mnt/arch_repo /mnt/arch_pkg_cache /mnt/backups; do
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" mkdir -p "$dir" || {
            err "Failed to create directory $dir"
            return 1
        }
    done

    # Set proper ownership and permissions for bigdata directories
    msg "Setting bigdata directory permissions..."
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" chgrp bigdata /mnt/arch_repo /mnt/arch_pkg_cache /mnt/backups || {
        err "Failed to set group ownership on bigdata directories"
        return 1
    }

    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" chmod g+w /mnt/arch_repo /mnt/arch_pkg_cache /mnt/backups || {
        err "Failed to set group write permissions on bigdata directories"
        return 1
    }

    # Set sticky bit so new files inherit group ownership
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" chmod g+s /mnt/arch_repo /mnt/arch_pkg_cache /mnt/backups || {
        err "Failed to set sticky bit on bigdata directories"
        return 1
    }

    msg "Group configuration completed"
}

# Step 11: Configure users
configure_users() {
    msg "Configuring users..."

    # Check if users.sh exists
    if [[ ! -f "$SCRIPT_DIR/users.sh" ]]; then
        err "users.sh not found at $SCRIPT_DIR/users.sh"
        return 1
    fi

    # Run users configuration
    "$SCRIPT_DIR/users.sh" -m "$MOUNT_ROOT" || {
        err "User configuration failed"
        return 1
    }

    msg "User configuration completed"
}

# Step 12: Sanity check - verify system is ready to boot
perform_sanity_check() {
    msg "Performing sanity check..."

    # Check if sanity.sh exists
    if [[ ! -f "$SCRIPT_DIR/sanity.sh" ]]; then
        err "sanity.sh not found at $SCRIPT_DIR/sanity.sh"
        return 1
    fi

    # Run sanity check
    "$SCRIPT_DIR/sanity.sh" "$MOUNT_ROOT" || {
        err "Sanity check failed - system may not boot properly"
        return 1
    }

    msg "Sanity check completed successfully"
}

# Execute installation steps
if [[ "$ANY_STEP_FLAG" == true ]]; then
    msg "Running selected installation steps in correct order..."

    # Count selected steps for progress tracking
    selected_steps=()
    [[ "$STEP_PARTITION" == true ]] && selected_steps+=("partition")
    [[ "$STEP_FORMAT" == true ]] && selected_steps+=("format")
    [[ "$STEP_MOUNT" == true ]] && selected_steps+=("mount")
    [[ "$STEP_BASE_SYSTEM" == true ]] && selected_steps+=("base-system")
    [[ "$STEP_CONFIGURE" == true ]] && selected_steps+=("configure")
    [[ "$STEP_BOOTLOADER" == true ]] && selected_steps+=("bootloader")
    [[ "$STEP_INITRAMFS" == true ]] && selected_steps+=("initramfs")
    [[ "$STEP_CONFIGURE_PACMAN" == true ]] && selected_steps+=("configure-pacman")
    [[ "$STEP_PACKAGES" == true ]] && selected_steps+=("packages")
    [[ "$STEP_NVIDIA" == true ]] && selected_steps+=("nvidia")
    [[ "$STEP_GROUPS" == true ]] && selected_steps+=("groups")
    [[ "$STEP_USERS" == true ]] && selected_steps+=("users")
    [[ "$STEP_SANITY" == true ]] && selected_steps+=("sanity")

    msg "Selected steps (${#selected_steps[@]}): ${selected_steps[*]}"
    echo

    # Run individual steps in correct order (always run in logical sequence)
    [[ "$STEP_PARTITION" == true ]] && {
        msg "Step 1: Partitioning device..."
        "$SCRIPT_DIR/partition.sh" || exit 1
        msg "✓ Partitioning completed"
        echo
    }
    [[ "$STEP_FORMAT" == true ]] && {
        msg "Step 2: Formatting partitions..."
        "$SCRIPT_DIR/format.sh" $([[ "$FORCE" == true ]] && echo "--force") || exit 1
        msg "✓ Formatting completed"
        echo
    }
    [[ "$STEP_MOUNT" == true ]] && {
        msg "Step 3: Mounting partitions..."
        "$SCRIPT_DIR/mount.sh" || exit 1
        msg "✓ Partitions mounted at $MOUNT_ROOT"
        echo
    }
    [[ "$STEP_BASE_SYSTEM" == true ]] && {
        msg "Step 4: Installing base system..."
        install_base_system || exit 1
        msg "✓ Base system installation completed"
        echo
    }
    [[ "$STEP_CONFIGURE" == true ]] && {
        msg "Step 5: Configuring system..."
        configure_system || exit 1
        msg "✓ System configuration completed"
        echo
    }
    [[ "$STEP_BOOTLOADER" == true ]] && {
        msg "Step 6: Setting up bootloader..."
        setup_bootloader || exit 1
        msg "✓ Bootloader setup completed"
        echo
    }
    [[ "$STEP_INITRAMFS" == true ]] && {
        msg "Step 7: Generating initramfs..."
        generate_initramfs || exit 1
        msg "✓ Initramfs generation completed"
        echo
    }
    [[ "$STEP_CONFIGURE_PACMAN" == true ]] && {
        msg "Step 8: Configuring pacman and repositories..."
        setup_pacman_and_repos || exit 1
        msg "✓ Pacman and repositories configuration completed"
        echo
    }
    [[ "$STEP_PACKAGES" == true ]] && {
        msg "Step 9: Installing packages..."
        install_packages || exit 1
        msg "✓ Package installation completed"
        echo
    }
    [[ "$STEP_NVIDIA" == true ]] && {
        msg "Step 9.5: Configuring NVIDIA modules..."
        configure_nvidia_modules || exit 1
        msg "✓ NVIDIA modules configuration completed"
        echo
    }
    [[ "$STEP_GROUPS" == true ]] && {
        msg "Step 10: Configuring groups..."
        configure_groups || exit 1
        msg "✓ Group configuration completed"
        echo
    }
    [[ "$STEP_USERS" == true ]] && {
        msg "Step 11: Configuring users..."
        configure_users || exit 1
        msg "✓ User configuration completed"
        echo
    }
    [[ "$STEP_SANITY" == true ]] && {
        msg "Step 12: Performing sanity check..."
        perform_sanity_check || exit 1
        msg "✓ Sanity check completed"
        echo
    }

    msg "All selected steps completed successfully!"
else
    msg "Starting Arch Linux installation..."

    # Step 1: Partition the device
    msg "Step 1: Partitioning device..."
    "$SCRIPT_DIR/partition.sh" || {
        err "Partitioning failed"
        exit 1
    }
    msg "Partitioning completed"

    # Step 2: Format partitions
    msg "Step 2: Formatting partitions..."
    "$SCRIPT_DIR/format.sh" $([[ "$FORCE" == true ]] && echo "--force") || {
        err "Formatting failed"
        exit 1
    }
    msg "Formatting completed"

    # Step 3: Mount partitions
    msg "Step 3: Mounting partitions..."
    "$SCRIPT_DIR/mount.sh" || {
        err "Mounting failed"
        exit 1
    }
    msg "Partitions mounted at $MOUNT_ROOT"

    install_base_system || exit 1
    configure_system || exit 1
    setup_bootloader || exit 1
    generate_initramfs || exit 1
    setup_pacman_and_repos || exit 1
    install_packages || exit 1
    configure_nvidia_modules || exit 1
    configure_groups || exit 1
    configure_users || exit 1
    perform_sanity_check || exit 1
fi

# Final cleanup of any remaining bind mounts
cleanup_repository_bind_mounts 2> /dev/null || true

# Final sync to ensure all data is written to disk
msg "Performing final sync to ensure all data is written to disk..."
sync
sleep 2

# Additional sync for good measure
sync
msg "All data synced to disk"

# Ask user if they want to unmount
ask_unmount

msg "Arch Linux installation completed successfully!"
msg "System features:"
msg "  - Hostname: $HOSTNAME"
msg "  - Users: root (custom password), jesusa (custom password, sudo access)"
msg "  - Default shell: fish"
msg "  - Services enabled: NetworkManager, sshd, gdm"
msg "  - Bootloader: GRUB with EFI support and NVIDIA modeset"
msg "  - NVIDIA: nvidia-open-dkms with proper kernel modules"
msg "  - Repository configured with NFS mounts and custom package cache"
echo
msg "The system is ready to boot. Remove installation media and reboot."
msg "Installation log saved to: $PWD/$LOG_FILE"
