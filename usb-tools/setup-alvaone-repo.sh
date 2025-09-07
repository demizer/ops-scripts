#!/bin/bash

# Alvaone Repository Setup Script for Arch Linux Live Environment
# Sets up the alvaone custom repository and package cache via NFS
# Based on create-usb-tools.sh but designed for live environment usage

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

msg "Setting up Alvaone repository for live environment"

# Install nfs-utils if not present
msg2 "Installing nfs-utils package..."
if ! pacman -Q nfs-utils &> /dev/null; then
    pacman -S --noconfirm nfs-utils
    if [[ $? -ne 0 ]]; then
        error "Failed to install nfs-utils"
        exit 1
    fi
else
    msg2 "nfs-utils already installed"
fi

# Mount NFS alvaone repository
msg2 "Mounting alvaone repository..."
REPO_MOUNT="/mnt/arch_repo"
REPO_SERVER="nas.alvaone.net:/mnt/bigdata/arch_repo/alvaone_repo"

if mountpoint -q "$REPO_MOUNT"; then
    msg2 "Alvaone repository already mounted at $REPO_MOUNT"
else
    mount --mkdir -o _netdev,noatime,nodiratime,rsize=131072,wsize=131072,timeo=600 "$REPO_SERVER" "$REPO_MOUNT"
    if mountpoint -q "$REPO_MOUNT"; then
        msg2 "Alvaone repository mounted successfully at $REPO_MOUNT"
    else
        error "Failed to mount alvaone repository"
        exit 1
    fi
fi

# Mount NFS package cache
msg2 "Mounting package cache..."
CACHE_MOUNT="/mnt/arch_pkg_cache"
CACHE_SERVER="nas.alvaone.net:/mnt/bigdata/arch_repo/pac_cache"

if mountpoint -q "$CACHE_MOUNT"; then
    msg2 "Package cache already mounted at $CACHE_MOUNT"
else
    mount --mkdir -o _netdev,noatime,nodiratime,rsize=131072,wsize=131072,timeo=600 "$CACHE_SERVER" "$CACHE_MOUNT"
    if mountpoint -q "$CACHE_MOUNT"; then
        msg2 "Package cache mounted successfully at $CACHE_MOUNT"
    else
        error "Failed to mount package cache"
        exit 1
    fi
fi

# Create alvaone repository configuration for live environment
msg2 "Creating alvaone repository configuration..."
ALVAONE_CONFIG="/etc/pacman.d/alvaone"

cat > "$ALVAONE_CONFIG" << 'EOF'
[alvaone]
SigLevel = Required
Server = file:///mnt/arch_repo/alvaone/$arch
EOF

if [[ $? -eq 0 ]]; then
    msg2 "Alvaone repository configuration created at $ALVAONE_CONFIG"
else
    error "Failed to create alvaone repository configuration"
    exit 1
fi

# Update pacman.conf to include alvaone configuration if not already present
msg2 "Updating pacman.conf to include alvaone repository..."
PACMAN_CONF="/etc/pacman.conf"

if ! grep -q "Include.*alvaone" "$PACMAN_CONF"; then
    # Add include before the standard repositories
    if grep -q "\\[core\\]" "$PACMAN_CONF"; then
        sed -i "/\\[core\\]/i\\Include = /etc/pacman.d/alvaone\\n" "$PACMAN_CONF"
        msg2 "Added alvaone repository include to pacman.conf"
    else
        # Fallback: append at the end
        echo -e "\nInclude = /etc/pacman.d/alvaone" >> "$PACMAN_CONF"
        msg2 "Appended alvaone repository include to pacman.conf"
    fi
else
    msg2 "Alvaone repository already included in pacman.conf"
fi

# Configure package cache directory if not already set
msg2 "Configuring package cache directory..."
if ! grep -q "^CacheDir.*$CACHE_MOUNT" "$PACMAN_CONF"; then
    # Check if CacheDir is already set
    if grep -q "^CacheDir" "$PACMAN_CONF"; then
        # Update existing CacheDir to use our NFS cache
        sed -i "s|^CacheDir.*|CacheDir = $CACHE_MOUNT/|" "$PACMAN_CONF"
        msg2 "Updated existing CacheDir configuration"
    else
        # Add CacheDir after [options] section
        if grep -q "\\[options\\]" "$PACMAN_CONF"; then
            sed -i "/\\[options\\]/a\\CacheDir = $CACHE_MOUNT/" "$PACMAN_CONF"
            msg2 "Added CacheDir configuration"
        else
            warning "Could not find [options] section in pacman.conf"
        fi
    fi
else
    msg2 "Cache directory already configured"
fi

# Import GPG keys for alvaone repository if available
msg2 "Checking for alvaone repository GPG keys..."
if [[ -d "$REPO_MOUNT/alvaone/x86_64" ]]; then
    # Try to find any signature files to determine if we need specific keys
    if find "$REPO_MOUNT/alvaone/x86_64" -name "*.sig" -type f | head -1 > /dev/null 2>&1; then
        msg2 "Repository appears to be signed - ensure GPG keys are imported manually if needed"
        msg2 "Run: pacman-key --recv-keys <KEY_ID> && pacman-key --lsign-key <KEY_ID>"
    else
        msg2 "Repository appears to be unsigned"
    fi
else
    warning "Repository directory structure not found - repository may not be properly set up"
fi

# Update package database
msg2 "Updating package database..."
pacman -Sy
if [[ $? -eq 0 ]]; then
    msg2 "Package database updated successfully"
else
    error "Failed to update package database"
    exit 1
fi

# Verify alvaone repository is accessible
msg2 "Verifying alvaone repository accessibility..."
if pacman -Sl alvaone > /dev/null 2>&1; then
    PACKAGE_COUNT=$(pacman -Sl alvaone 2> /dev/null | wc -l)
    msg2 "Alvaone repository is accessible with $PACKAGE_COUNT packages"
else
    warning "Alvaone repository is not accessible - check GPG keys or repository setup"
fi

msg "Alvaone repository setup completed successfully!"
msg2 "Services configured:"
msg2 "  - Alvaone repository mounted at $REPO_MOUNT"
msg2 "  - Package cache mounted at $CACHE_MOUNT"
msg2 "  - Pacman configured to use alvaone repository"
msg2 "  - Package database updated"
msg2 ""
msg2 "Usage:"
msg2 "  - Install packages: pacman -S <package-name>"
msg2 "  - Search alvaone packages: pacman -Ss --repo alvaone <search-term>"
msg2 "  - List all alvaone packages: pacman -Sl alvaone"
