#!/bin/bash

# USB Tools System Creator
# Creates a portable Arch Linux system on USB using pacstrap
# Designed for system administration and troubleshooting tasks

# Color output functions (matching other scripts)
unset ALL_OFF BOLD BLUE GREEN RED YELLOW

if tput setaf 0 &> /dev/null; then
    ALL_OFF="$(tput sgr0)"
    BOLD="$(tput bold)"
    BLUE="${BOLD}$(tput setaf 4)"
    GREEN="${BOLD}$(tput setaf 2)"
    RED="${BOLD}$(tput setaf 1)"
    YELLOW="${BOLD}$(tput setaf 3)"
else
    ALL_OFF="\\e[1;0m"
    BOLD="\\e[1;1m"
    BLUE="${BOLD}\\e[1;34m"
    GREEN="${BOLD}\\e[1;32m"
    RED="${BOLD}\\e[1;31m"
    YELLOW="${BOLD}\\e[1;33m"
fi

readonly ALL_OFF BOLD BLUE GREEN RED YELLOW

msg() {
    local mesg=$1
    shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2
}

msg2() {
    local mesg=$1
    shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2
}

warning() {
    local mesg=$1
    shift
    printf "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2
}

error() {
    local mesg=$1
    shift
    printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2
}

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    error "This script must be run as root"
    exit 1
fi

# Check if running on Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    error "This script must be run on Arch Linux"
    exit 1
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE=""
MOUNT_ROOT="/mnt/usb-tools"
MOUNT_EFI="/mnt/usb-tools-efi"

# Package list - based on archiso but optimized for tools
PACKAGES=(
    # Base system
    base linux linux-firmware

    # Essential tools
    bash-completion fish tmux
    openssh sudo

    # System tools
    util-linux coreutils findutils grep sed gawk
    procps-ng psmisc which

    # Hardware tools
    pciutils usbutils lshw dmidecode
    smartmontools hdparm sdparm

    # Network tools
    iproute2 iputils netctl dhcpcd
    nfs-utils rsync wget curl
    msmtp

    # Network debugging and analysis tools
    bind           # dig, nslookup, host
    traceroute mtr # Network path tracing
    nmap           # Network scanning
    tcpdump        # Packet capture and analysis
    iftop nethogs  # Network usage monitoring
    ethtool        # Ethernet interface configuration
    bridge-utils   # Bridge configuration utilities
    wireless_tools # iwconfig, iwlist for WiFi
    wpa_supplicant # WiFi authentication
    openbsd-netcat # Network connectivity testing
    socat          # Socket relay and tunneling
    iperf3 iperf   # Network performance testing

    # File system tools
    e2fsprogs dosfstools ntfs-3g
    btrfs-progs xfsprogs

    # Archive tools
    tar gzip bzip2 xz unzip zip

    # Development tools
    git neovim

    # Monitoring tools
    htop iotop lsof strace

    # Text processing
    less man-db man-pages

    # Testing tools
    memtest86+-efi

    # Recovery and forensics tools
    ddrescue testdisk
    foremost

    # Disk tools
    parted

    # Security tools
    gnupg

    # Additional useful tools
    screen tmux
    tree mc
    ncdu

    # Tools needed by ops-scripts and self-reproduction
    arch-install-scripts # pacstrap, genfstab, arch-chroot
    gptfdisk             # sgdisk for partitioning
    dosfstools           # mkfs.fat for EFI partition
    libarchive           # bsdtar for archive operations
    squashfs-tools       # unsquashfs (if needed for ISO operations)

    # Build and development tools
    base-devel        # Essential build tools
    python python-pip # For Python scripts

    # Additional system tools
    lsof strace ltrace # System debugging

    # Backup and sync tools (for ops-scripts)
    rsync rclone # File synchronization

    # Compression tools
    p7zip unrar # Additional archive formats
)

show_help() {
    cat << EOF
Usage: $0 --device DEVICE [OPTIONS]

Create a portable Arch Linux tools system on USB device

REQUIRED:
    --device DEVICE     Target USB device (e.g., /dev/sdb, /dev/mmcblk0)

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    --bridge-password   Proton Mail Bridge password for email setup

EXAMPLES:
    $0 --device /dev/sdb
    $0 --device /dev/mmcblk0 --force
    $0 --device /dev/sdb --bridge-password "mypassword"

EOF
}

# Parse command line arguments
FORCE=false
BRIDGE_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        --device)
            DEVICE="$2"
            shift 2
            ;;
        -f | --force)
            FORCE=true
            shift
            ;;
        --bridge-password)
            BRIDGE_PASSWORD="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate device argument
if [[ -z "$DEVICE" ]]; then
    error "Device must be specified with --device"
    show_help
    exit 1
fi

if [[ ! -e "$DEVICE" ]]; then
    error "Device not found: $DEVICE"
    exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
    error "Not a block device: $DEVICE"
    exit 1
fi

msg "Creating USB Tools System on $DEVICE"

# Show device information
msg2 "Target device info:"
lsblk "$DEVICE" 2> /dev/null | sed 's/^/    /' || {
    error "Failed to read device information"
    exit 1
}

# Confirmation unless --force
if [[ "$FORCE" != true ]]; then
    echo
    warning "This will completely destroy all data on $DEVICE!"
    read -p "Are you sure you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        msg2 "Operation cancelled"
        exit 0
    fi
fi

msg "Starting USB tools system creation..."

# Function to cleanup on exit
cleanup() {
    if mountpoint -q "$MOUNT_ROOT" 2> /dev/null; then
        msg2 "Cleaning up: unmounting $MOUNT_ROOT"
        umount -R "$MOUNT_ROOT" 2> /dev/null
    fi
    if mountpoint -q "$MOUNT_EFI" 2> /dev/null; then
        msg2 "Cleaning up: unmounting $MOUNT_EFI"
        umount "$MOUNT_EFI" 2> /dev/null
    fi
}

trap cleanup EXIT

# Step 1: Partition the device
partition_device() {
    msg2 "Partitioning device..."

    # Unmount any existing partitions - more aggressive approach
    msg2 "Unmounting any existing partitions..."

    # Find all partitions on this device
    for part in "${DEVICE}"*; do
        if [[ "$part" != "$DEVICE" ]]; then
            # Force unmount if mounted
            if mountpoint -q "$part" 2> /dev/null; then
                msg2 "Unmounting $part"
                umount "$part" 2> /dev/null || umount -f "$part" 2> /dev/null || true
            fi

            # Also check if it's used by any process
            fuser -km "$part" 2> /dev/null || true
        fi
    done

    # Give the system time to release the device
    sleep 2

    # Create GPT partition table
    sgdisk --zap-all "$DEVICE" || {
        error "Failed to clear partition table"
        return 1
    }

    # Create partitions: 1GB EFI + 2GB swap + remainder ext4
    sgdisk --clear \
        --new=1:1MiB:+1GiB --typecode=1:ef00 --change-name=1:ARCHISO_EFI \
        --new=2:0:+2GiB --typecode=2:8200 --change-name=2:ARCHISO_SWAP \
        --new=3:0:0 --typecode=3:8300 --change-name=3:ARCHISO_ROOT \
        "$DEVICE" || {
        error "Failed to create partitions"
        return 1
    }

    # Sync partition table changes to disk
    sync

    # Refresh partition table and wait for kernel to recognize changes
    msg2 "Refreshing partition table..."
    partprobe "$DEVICE" || true
    udevadm settle || true
    sleep 3

    # Force kernel to re-read partition table
    blockdev --rereadpt "$DEVICE" 2> /dev/null || true
    sync
    sleep 2

    # Determine partition paths
    if [[ "$DEVICE" =~ mmcblk|nvme ]]; then
        EFI_PART="${DEVICE}p1"
        SWAP_PART="${DEVICE}p2"
        ROOT_PART="${DEVICE}p3"
    else
        EFI_PART="${DEVICE}1"
        SWAP_PART="${DEVICE}2"
        ROOT_PART="${DEVICE}3"
    fi

    # Wait for partitions to appear
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if [[ -e "$EFI_PART" && -e "$SWAP_PART" && -e "$ROOT_PART" ]]; then
            break
        fi
        sleep 1
        ((retries--))
    done

    if [[ ! -e "$EFI_PART" || ! -e "$SWAP_PART" || ! -e "$ROOT_PART" ]]; then
        error "Partitions failed to appear"
        return 1
    fi

    msg2 "Created partitions: $EFI_PART (EFI), $SWAP_PART (swap), $ROOT_PART (root)"
}

# Step 2: Format partitions
format_partitions() {
    msg2 "Formatting partitions..."

    # Ensure partitions are not in use before formatting
    for part in "$EFI_PART" "$SWAP_PART" "$ROOT_PART"; do
        if mountpoint -q "$part" 2> /dev/null; then
            msg2 "Force unmounting $part"
            umount -f "$part" 2> /dev/null || true
        fi

        # Kill any processes using the partition
        fuser -km "$part" 2> /dev/null || true

        # Wait for processes to die
        sleep 1
    done

    # Format EFI partition
    mkfs.fat -F32 -n ARCHISO_EFI "$EFI_PART" || {
        error "Failed to format EFI partition: $EFI_PART"
        error "Try unplugging and replugging the USB device, then run again"
        return 1
    }

    # Sync EFI partition creation
    sync

    # Format swap partition
    mkswap -L ARCHISO_SWAP "$SWAP_PART" || {
        error "Failed to format swap partition: $SWAP_PART"
        error "Try unplugging and replugging the USB device, then run again"
        return 1
    }

    # Sync swap partition creation
    sync

    # Format root partition
    mkfs.ext4 -F -L ARCHISO_ROOT "$ROOT_PART" || {
        error "Failed to format root partition: $ROOT_PART"
        error "Try unplugging and replugging the USB device, then run again"
        return 1
    }

    # Sync root partition creation
    sync
    sleep 1

    msg2 "Partitions formatted successfully (EFI, swap, root)"
}

# Step 3: Mount partitions
mount_partitions() {
    msg2 "Mounting partitions..."

    # Create mount points
    mkdir -p "$MOUNT_ROOT" "$MOUNT_EFI"

    # Mount root partition
    mount "$ROOT_PART" "$MOUNT_ROOT" || {
        error "Failed to mount root partition"
        return 1
    }

    # Create and mount EFI directory
    mkdir -p "$MOUNT_ROOT/boot"
    mount "$EFI_PART" "$MOUNT_ROOT/boot" || {
        error "Failed to mount EFI partition"
        return 1
    }

    msg2 "Partitions mounted at $MOUNT_ROOT"
}

# Step 4: Install base system with pacstrap
install_base_system() {
    msg2 "Installing base system with pacstrap..."

    # Check if pacstrap is available
    if ! command -v pacstrap &> /dev/null; then
        error "pacstrap not found. Please install arch-install-scripts"
        return 1
    fi

    # Run pacstrap to install packages
    pacstrap -c "$MOUNT_ROOT" --noconfirm "${PACKAGES[@]}" || {
        error "Failed to install base system"
        return 1
    }

    # Sync after package installation
    sync
    msg2 "Base system installed successfully"
}

# Execute the steps
partition_device || exit 1
format_partitions || exit 1
mount_partitions || exit 1
install_base_system || exit 1

# Step 5: Configure the system
configure_system() {
    msg2 "Configuring system..."

    # Generate fstab
    genfstab -U "$MOUNT_ROOT" >> "$MOUNT_ROOT/etc/fstab" || {
        error "Failed to generate fstab"
        return 1
    }

    # Ensure no conflicting swap entries exist
    msg2 "Cleaning up fstab for proper swap configuration..."
    # Remove any swapfile entries that might interfere
    sed -i '/\/home\/swapfile/d' "$MOUNT_ROOT/etc/fstab"
    sed -i '/\/swapfile/d' "$MOUNT_ROOT/etc/fstab"

    # Set hostname
    echo "alvaone-tools" > "$MOUNT_ROOT/etc/hostname"

    # Configure locale
    echo "en_US.UTF-8 UTF-8" > "$MOUNT_ROOT/etc/locale.gen"
    echo "LANG=en_US.UTF-8" > "$MOUNT_ROOT/etc/locale.conf"

    # Set timezone
    arch-chroot "$MOUNT_ROOT" ln -sf /usr/share/zoneinfo/UTC /etc/localtime

    # Generate locale
    arch-chroot "$MOUNT_ROOT" locale-gen

    # Set root password to 'alvaone'
    echo 'root:alvaone' | arch-chroot "$MOUNT_ROOT" chpasswd

    # Enable essential services
    arch-chroot "$MOUNT_ROOT" systemctl enable sshd
    arch-chroot "$MOUNT_ROOT" systemctl enable systemd-networkd
    arch-chroot "$MOUNT_ROOT" systemctl enable systemd-resolved

    # Configure automatic wired network connection
    msg2 "Configuring automatic wired network connection..."
    mkdir -p "$MOUNT_ROOT/etc/systemd/network"
    cat > "$MOUNT_ROOT/etc/systemd/network/20-wired.network" << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCP]
RouteMetric=10
EOF

    # Disable any automatic swapfile creation services
    arch-chroot "$MOUNT_ROOT" systemctl mask systemd-swap || true

    # Ensure no existing swap configuration files interfere
    rm -f "$MOUNT_ROOT/etc/systemd/swap.conf" 2> /dev/null || true
    rm -f "$MOUNT_ROOT/etc/systemd/swap.conf.d/"* 2> /dev/null || true

    # Configure SSH for better rsync/scp support
    msg2 "Configuring SSH server..."
    mkdir -p "$MOUNT_ROOT/etc/ssh/sshd_config.d"
    cat > "$MOUNT_ROOT/etc/ssh/sshd_config.d/99-usb-tools.conf" << 'EOF'
# USB Tools SSH Configuration
# Optimized for rsync/scp operations

# Allow root login (live environment)
PermitRootLogin yes

# Performance optimizations for file transfers
Compression yes
TCPKeepAlive yes

# Increase max sessions for concurrent transfers
MaxSessions 10
MaxStartups 10:30:60

# Allow large file transfers
ClientAliveInterval 60
ClientAliveCountMax 3

# Disable unnecessary authentication methods for speed
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# Enable password authentication (live environment)
PasswordAuthentication yes
PubkeyAuthentication yes

# Optimize for LAN usage
UseDNS no
EOF

    # Generate SSH host keys
    arch-chroot "$MOUNT_ROOT" ssh-keygen -A

    # Set up convenient directory structure for file transfers
    mkdir -p "$MOUNT_ROOT/workspace/uploads"
    mkdir -p "$MOUNT_ROOT/workspace/downloads"

    # Create .ssh directory for root
    mkdir -p "$MOUNT_ROOT/root/.ssh"
    chmod 700 "$MOUNT_ROOT/root/.ssh"

    # Create a info file for SSH users
    cat > "$MOUNT_ROOT/root/README-ssh.txt" << 'EOF'
SSH Access Information:
- Username: root
- Password: alvaone
- Add your public key to /root/.ssh/authorized_keys for passwordless access

Convenient directories:
- /workspace          - ops-scripts repository
- /workspace/uploads  - upload files here
- /workspace/downloads - download files from here

Example rsync usage:
  rsync -av /local/files/ root@<usb-ip>:/workspace/uploads/
  rsync -av root@<usb-ip>:/workspace/ /local/backup/
EOF

    msg2 "System configured successfully"
}

# Step 6: Install and configure systemd-boot
setup_bootloader() {
    msg2 "Setting up systemd-boot bootloader..."

    # Install systemd-boot
    arch-chroot "$MOUNT_ROOT" bootctl install || {
        error "Failed to install systemd-boot"
        return 1
    }

    # Copy memtest86+ EFI binary - try multiple possible locations
    MEMTEST_INSTALLED=false
    MEMTEST_LOCATIONS=(
        "$MOUNT_ROOT/usr/share/memtest86+-efi/memtest.efi"
        "$MOUNT_ROOT/usr/lib/memtest86+-efi/memtest.efi"
        "$MOUNT_ROOT/usr/share/memtest86+/memtest.efi"
        "$MOUNT_ROOT/usr/lib/memtest86+/memtest.efi"
        "$MOUNT_ROOT/boot/memtest86+/memtest.efi"
    )

    for memtest_path in "${MEMTEST_LOCATIONS[@]}"; do
        if [[ -f "$memtest_path" ]]; then
            mkdir -p "$MOUNT_ROOT/boot/memtest86+"
            cp "$memtest_path" "$MOUNT_ROOT/boot/memtest86+/memtest.efi"
            msg2 "Memtest86+ installed to boot partition from: $memtest_path"
            MEMTEST_INSTALLED=true
            break
        fi
    done

    if [[ "$MEMTEST_INSTALLED" == false ]]; then
        msg2 "Memtest86+ EFI binary not found in expected locations - checking system..."
        # Try to find memtest anywhere in the system
        if memtest_found=$(find "$MOUNT_ROOT" -name "memtest*.efi" -type f 2> /dev/null | head -1); then
            if [[ -n "$memtest_found" ]]; then
                mkdir -p "$MOUNT_ROOT/boot/memtest86+"
                cp "$memtest_found" "$MOUNT_ROOT/boot/memtest86+/memtest.efi"
                msg2 "Memtest86+ installed from: $memtest_found"
                MEMTEST_INSTALLED=true
            fi
        fi
    fi

    if [[ "$MEMTEST_INSTALLED" == false ]]; then
        msg2 "Memtest86+ EFI binary not found - memtest boot entry will be skipped"
    fi

    # Create loader configuration
    cat > "$MOUNT_ROOT/boot/loader/loader.conf" << 'EOF'
default  01-alvaone-tools.conf
timeout  4
console-mode keep
editor   no
EOF

    # Create boot entries directory
    mkdir -p "$MOUNT_ROOT/boot/loader/entries"

    # Main boot entry
    cat > "$MOUNT_ROOT/boot/loader/entries/01-alvaone-tools.conf" << 'EOF'
title    Alvaone System Tools
sort-key 01
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=LABEL=ARCHISO_ROOT rw quiet
EOF

    # Fallback boot entry (verbose)
    cat > "$MOUNT_ROOT/boot/loader/entries/02-alvaone-tools-fallback.conf" << 'EOF'
title    Alvaone System Tools (Fallback)
sort-key 02
linux    /vmlinuz-linux
initrd   /initramfs-linux-fallback.img
options  root=LABEL=ARCHISO_ROOT rw
EOF

    # Emergency shell entry
    cat > "$MOUNT_ROOT/boot/loader/entries/03-emergency.conf" << 'EOF'
title    Emergency Shell
sort-key 03
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=LABEL=ARCHISO_ROOT rw systemd.unit=emergency.target
EOF

    # Memory test entry (only if memtest was successfully installed)
    if [[ "$MEMTEST_INSTALLED" == true ]]; then
        cat > "$MOUNT_ROOT/boot/loader/entries/04-memtest.conf" << 'EOF'
title    Memory Test (Memtest86+)
sort-key 04
efi      /memtest86+/memtest.efi
EOF
        msg2 "Memtest86+ boot entry created"
    else
        msg2 "Skipping memtest boot entry - binary not available"
    fi

    # EFI Shell entry (if available)
    if [[ -f "$MOUNT_ROOT/boot/shellx64.efi" ]]; then
        cat > "$MOUNT_ROOT/boot/loader/entries/05-efi-shell.conf" << 'EOF'
title    EFI Shell
sort-key 05
efi      /shellx64.efi
EOF
    fi

    msg2 "Bootloader configured successfully"
}

# Step 7: Generate initramfs
generate_initramfs() {
    msg2 "Generating initramfs..."

    # Create standard mkinitcpio configuration
    cat > "$MOUNT_ROOT/etc/mkinitcpio.conf" << 'EOF'
# Standard mkinitcpio configuration for tools system
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOF

    # Generate initramfs
    arch-chroot "$MOUNT_ROOT" mkinitcpio -P || {
        error "Failed to generate initramfs"
        return 1
    }

    # Sync after initramfs generation
    sync
    msg2 "Initramfs generated successfully"
}

# Step 8: Apply archiso-style customizations
apply_customizations() {
    msg2 "Applying archiso-style customizations..."

    # Set up auto-login for root on tty1
    mkdir -p "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d"
    cat > "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

    # Set bash as default shell for root (rsync compatibility)
    arch-chroot "$MOUNT_ROOT" chsh -s /bin/bash root

    # Create fish configuration directory
    mkdir -p "$MOUNT_ROOT/root/.config/fish"

    # Set up neovim configuration
    msg2 "Setting up neovim configuration..."
    mkdir -p "$MOUNT_ROOT/root/.config/nvim"

    # Copy the nvim.lua configuration as init.lua
    if [[ -f "$HOME/.config/nvim/nvim.lua" ]]; then
        cp "$HOME/.config/nvim/nvim.lua" "$MOUNT_ROOT/root/.config/nvim/init.lua"
        msg2 "Neovim configuration installed"
    else
        msg2 "Warning: nvim.lua not found at $HOME/.config/nvim/nvim.lua - skipping neovim config"
    fi

    # Create fish configuration with archiso-style setup
    cat > "$MOUNT_ROOT/root/.config/fish/config.fish" << 'EOF'
# Alvaone System Tools fish configuration
set -g fish_greeting "Welcome to Alvaone System Tools"

# Load environment variables from systemd environment files
if test -d /etc/environment.d
    for file in /etc/environment.d/*.conf
        if test -f $file
            # Parse environment file and set variables in fish
            while read -l line
                if test -n "$line"; and not string match -q '#*' "$line"
                    set -l parts (string split '=' "$line" -m 1)
                    if test (count $parts) -eq 2
                        set -gx $parts[1] (string trim -c '"' $parts[2])
                    end
                end
            end < $file
        end
    end
end

# Start tmux session if not already in one and in an interactive terminal
if command -v tmux >/dev/null 2>&1; and not set -q TMUX; and status is-interactive; and isatty stdin; and isatty stdout
    set SESSION_NAME "main"
    # Create session if it doesn't exist
    if not tmux has-session -t "$SESSION_NAME" 2>/dev/null
        # Create session in workspace directory
        tmux new-session -d -s "$SESSION_NAME" -c /workspace
        # Set up multiple windows
        tmux rename-window -t "$SESSION_NAME:0" "ops-scripts"
        tmux new-window -t "$SESSION_NAME" -n "monitoring" -c /
        tmux new-window -t "$SESSION_NAME" -n "network" -c /
        # Return to first window
        tmux select-window -t "$SESSION_NAME:0"
    end
    exec tmux attach-session -t "$SESSION_NAME"
end

# Add helpful aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Show MOTD only once using sentinel file
set MOTD_SHOWN_FILE "/tmp/.motd_shown"
if not test -f $MOTD_SHOWN_FILE
    bash /root/motd.sh
    touch $MOTD_SHOWN_FILE
end

# Change to workspace directory
if test -d /workspace
    cd /workspace
end

# Display available tools
echo "Available tools:"
echo "  - ops-scripts: mount-nfs, tar-backup, rsync-backup, pvt.sh"
echo "  - Network diagnostics: nmap, iperf3, mtr, tcpdump, traceroute"
echo "  - Disk recovery: ddrescue, testdisk, photorec, foremost"
echo "  - System monitoring: htop, iotop, lsof, strace"
echo "  - File management: mc, tree, ncdu"
echo
EOF

    # Create MOTD script
    cat > "$MOUNT_ROOT/root/motd.sh" << 'EOF'
#!/usr/bin/env bash

echo
echo " █████╗ ██╗    ██╗   ██╗ █████╗  ██████╗ ███╗   ██╗███████╗"
echo "██╔══██╗██║    ██║   ██║██╔══██╗██╔═══██╗████╗  ██║██╔════╝"
echo "███████║██║    ██║   ██║███████║██║   ██║██╔██╗ ██║█████╗"
echo "██╔══██║██║    ╚██╗ ██╔╝██╔══██║██║   ██║██║╚██╗██║██╔══╝"
echo "██║  ██║███████╗╚████╔╝ ██║  ██║╚██████╔╝██║ ╚████║███████╗"
echo "╚═╝  ╚═╝╚══════╝ ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝"
echo " ██╗     ██╗██╗   ██╗███████╗"
echo " ██║     ██║██║   ██║██╔════╝"
echo " ██║     ██║██║   ██║█████╗"
echo " ██║     ██║╚██╗ ██╔╝██╔══╝"
echo " ███████╗██║ ╚████╔╝ ███████╗"
echo " ╚══════╝╚═╝  ╚═══╝  ╚══════╝"
echo
echo "Network: SSH daemon is enabled and running"
echo "Username: root"
echo "Password: alvaone"
echo
echo "Shell: Default is bash (rsync compatible)"
echo "       Type 'fish' to start fish shell with tmux"
echo
EOF

    chmod +x "$MOUNT_ROOT/root/motd.sh"

    # Create environment file with bridge password if provided
    if [[ -n "$BRIDGE_PASSWORD" ]]; then
        mkdir -p "$MOUNT_ROOT/etc/environment.d"
        cat > "$MOUNT_ROOT/etc/environment.d/99-bridge.conf" << EOF
BRIDGE_PASSWORD="$BRIDGE_PASSWORD"
EOF
        chmod 600 "$MOUNT_ROOT/etc/environment.d/99-bridge.conf"
        msg2 "Bridge password configured"
    fi

    msg2 "Archiso-style customizations applied"
}

# Step 9: Copy ops-scripts to workspace
copy_ops_scripts() {
    msg2 "Copying ops-scripts to workspace directory..."

    # Find ops-scripts directory
    local ops_scripts_dir="$SCRIPT_DIR/.."

    if [[ ! -d "$ops_scripts_dir/.git" ]]; then
        msg2 "ops-scripts directory not found - skipping script copy"
        return 0
    fi

    # Create workspace directory
    mkdir -p "$MOUNT_ROOT/workspace"

    # Change to ops-scripts directory and copy git-tracked files
    cd "$ops_scripts_dir"

    local copied_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            local dest_file="$MOUNT_ROOT/workspace/$file"
            local dest_dir=$(dirname "$dest_file")
            mkdir -p "$dest_dir"
            cp "$file" "$dest_file"
            ((copied_count++))
        fi
    done < <(git ls-files -z 2> /dev/null)

    # Copy .git directory
    if [[ -d "$ops_scripts_dir/.git" ]]; then
        cp -r "$ops_scripts_dir/.git" "$MOUNT_ROOT/workspace/"
        msg2 "Copied .git directory"
    fi

    # Make shell scripts executable
    find "$MOUNT_ROOT/workspace" -name "*.sh" -exec chmod +x {} \;

    # Create symlinks in /usr/bin for main ops-scripts tools
    msg2 "Creating symlinks for ops-scripts tools in /usr/bin..."

    # List of main tools to make available system-wide
    local tools_to_link=(
        "usb-tools/mount-nfs.sh:mount-nfs"
        "usb-tools/create-usb-tools.sh:create-usb-tools"
        "backup/tar-backup.sh:tar-backup"
        "usb-tools/test-usb-tools.sh:test-usb-tools"
    )

    for tool_mapping in "${tools_to_link[@]}"; do
        local source_path="${tool_mapping%:*}"
        local link_name="${tool_mapping#*:}"
        local full_source="/workspace/$source_path"
        local link_target="/usr/bin/$link_name"

        if [[ -f "$MOUNT_ROOT$full_source" ]]; then
            ln -sf "$full_source" "$MOUNT_ROOT$link_target"
            msg2 "Created symlink: $link_name -> $full_source"
        fi
    done

    msg2 "Copied $copied_count files to workspace directory"
}

# Execute all configuration steps
configure_system || exit 1
setup_bootloader || exit 1
generate_initramfs || exit 1
apply_customizations || exit 1
copy_ops_scripts || exit 1

# Final sync to ensure all data is written to disk
msg2 "Performing final sync to ensure all data is written to disk..."
sync
sleep 2

# Sync filesystem buffers for the specific device
if command -v fsync &> /dev/null; then
    fsync "$MOUNT_ROOT" 2> /dev/null || true
fi

# Additional sync for good measure
sync
msg2 "All data synced to disk"

msg "USB Tools System created successfully!"
msg2 "System features:"
msg2 "  - Auto-login as root with fish shell"
msg2 "  - Archiso-style MOTD and branding"
msg2 "  - SSH enabled on boot (password: alvaone)"
msg2 "  - Comprehensive system administration tools"
msg2 "  - Memory testing and emergency boot options"
msg2 "  - ops-scripts available in /workspace/"
echo
msg2 "To test in QEMU: sudo $SCRIPT_DIR/test-usb-tools-qemu.sh --no-host-networking --device $DEVICE"
