#!/bin/bash

# Custom Arch ISO Build Script
# Creates a custom archiso with:
# - Fish shell as default
# - Included setup scripts (setup-archiso-env.sh, setup-sendmail-bridge.sh)
# - Pre-configured environment

# Color output functions (matching other scripts)
unset ALL_OFF BOLD BLUE GREEN RED YELLOW

if tput setaf 0 &>/dev/null; then
    ALL_OFF="$(tput sgr0)";
    BOLD="$(tput bold)";
    BLUE="${BOLD}$(tput setaf 4)";
    GREEN="${BOLD}$(tput setaf 2)";
    RED="${BOLD}$(tput setaf 1)";
    YELLOW="${BOLD}$(tput setaf 3)";
else
    ALL_OFF="\\e[1;0m";
    BOLD="\\e[1;1m";
    BLUE="${BOLD}\\e[1;34m";
    GREEN="${BOLD}\\e[1;32m";
    RED="${BOLD}\\e[1;31m";
    YELLOW="${BOLD}\\e[1;33m";
fi

readonly ALL_OFF BOLD BLUE GREEN RED YELLOW;

msg() {
    local mesg=$1; shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

msg2() {
    local mesg=$1; shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

warning() {
    local mesg=$1; shift
    printf "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

error() {
    local mesg=$1; shift
    printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\\n" "$@" >&2;
}

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    error "This script must be run as root";
    exit 1;
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/archiso-custom"
PROFILE_DIR="$BUILD_DIR/profile"
OUTPUT_DIR="/tmp/archiso-output"

msg "Creating custom Arch Linux ISO with fish shell and setup scripts";

# Clean up previous builds
if [[ -d "$BUILD_DIR" ]]; then
    msg2 "Cleaning up previous build directory...";
    rm -rf "$BUILD_DIR"
fi

if [[ -d "$OUTPUT_DIR" ]]; then
    msg2 "Cleaning up previous output directory...";
    rm -rf "$OUTPUT_DIR"
fi

# Install archiso if not present
msg2 "Installing archiso package...";
if ! pacman -Q archiso &>/dev/null; then
    pacman -S --noconfirm archiso
else
    msg2 "archiso already installed";
fi

# Create build directory and copy baseline profile
msg2 "Setting up build environment...";
mkdir -p "$BUILD_DIR"
cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"

# Customize packages.x86_64 to include fish and other packages
msg2 "Customizing package list...";
cat >> "$PROFILE_DIR/packages.x86_64" << 'EOF'

# Custom additions
fish
tmux
nfs-utils
msmtp
neovim
EOF

# Create airootfs structure for custom files
msg2 "Creating custom file structure...";
mkdir -p "$PROFILE_DIR/airootfs/root"
mkdir -p "$PROFILE_DIR/airootfs/etc/skel"

# Copy entire ops-scripts directory to the ISO
msg2 "Including ops-scripts directory in ISO...";
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -d "$PARENT_DIR" ]]; then
    cp -r "$PARENT_DIR" "$PROFILE_DIR/airootfs/root/scripts"

    # Make all shell scripts executable
    find "$PROFILE_DIR/airootfs/root/scripts" -name "*.sh" -type f -exec chmod +x {} \;

    msg2 "Copied ops-scripts directory with all files and git history";
else
    error "ops-scripts parent directory not found at $PARENT_DIR";
    exit 1;
fi

# Set fish as default shell for root
msg2 "Configuring fish as default shell...";
mkdir -p "$PROFILE_DIR/airootfs/root"
cat > "$PROFILE_DIR/airootfs/root/.bashrc" << 'EOF'
# Auto-switch to fish if available and not already in fish
if command -v fish >/dev/null 2>&1 && [ -z "$FISH_VERSION" ]; then
    # Start tmux session if not already in one
    if command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
        SESSION_NAME="main"
        if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux new-session -d -s "$SESSION_NAME" fish
        fi
        exec tmux attach-session -t "$SESSION_NAME"
    else
        exec fish
    fi
fi
EOF

# Create fish configuration
mkdir -p "$PROFILE_DIR/airootfs/root/.config/fish"
cat > "$PROFILE_DIR/airootfs/root/.config/fish/config.fish" << 'EOF'
# Custom fish configuration for Arch ISO
set -g fish_greeting "Welcome to Alvaone Arch Linux Live Environment"

# Add helpful aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Display setup instructions on login
echo "Alvaone Arch Linux Live Environment Ready!"
echo "Tmux session started automatically."
echo
echo "Available scripts:"
echo "  - ./mount-nfs        # Mount NFS backups share"
echo "  - ./setup-email      # Configure email bridge"
echo ""
echo "Example: sudo ./mount-nfs"
echo
EOF

# Create a customize_airootfs.sh script to set fish as default shell
msg2 "Creating customization script...";
cat > "$PROFILE_DIR/airootfs/root/customize_airootfs.sh" << 'EOF'
#!/usr/bin/env bash

set -e -u

# Set fish as default shell for root
if command -v fish >/dev/null 2>&1; then
    chsh -s /usr/bin/fish root
fi

# Enable SSH service by default
systemctl enable sshd
systemctl start sshd

# Create symlinks for easy access to scripts
ln -sf /root/scripts/archiso/mount-nfs.sh /root/mount-nfs
ln -sf /root/scripts/archiso/setup-sendmail-bridge.sh /root/setup-email

# Set executable permissions on all scripts (already done during copy)
find /root/scripts -name "*.sh" -type f -exec chmod +x {} \;
EOF

chmod +x "$PROFILE_DIR/airootfs/root/customize_airootfs.sh"

# Modify the main customize_airootfs.sh if it exists
if [[ -f "$PROFILE_DIR/airootfs/root/customize_airootfs.sh.orig" ]]; then
    mv "$PROFILE_DIR/airootfs/root/customize_airootfs.sh.orig" "$PROFILE_DIR/airootfs/root/customize_airootfs.sh.orig.bak"
fi

# Create welcome message
msg2 "Creating welcome message...";
cat > "$PROFILE_DIR/airootfs/etc/motd" << 'EOF'

 █████╗ ██╗    ██╗   ██╗ █████╗  ██████╗ ███╗   ██╗███████╗
██╔══██╗██║    ██║   ██║██╔══██╗██╔═══██╗████╗  ██║██╔════╝
███████║██║    ██║   ██║███████║██║   ██║██╔██╗ ██║█████╗
██╔══██║██║    ╚██╗ ██╔╝██╔══██║██║   ██║██║╚██╗██║██╔══╝
██║  ██║███████╗╚████╔╝ ██║  ██║╚██████╔╝██║ ╚████║███████╗
╚═╝  ╚═╝╚══════╝ ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

 █████╗ ██████╗  ██████╗██╗  ██╗    ██╗███████╗ ██████╗
██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║██╔════╝██╔═══██╗
███████║██████╔╝██║     ███████║    ██║███████╗██║   ██║
██╔══██║██╔══██╗██║     ██╔══██║    ██║╚════██║██║   ██║
██║  ██║██║  ██║╚██████╗██║  ██║    ██║███████║╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝╚══════╝ ╚═════╝

Default shell: fish
Mount NFS: ./mount-nfs
Setup email: ./setup-email

EOF

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build the ISO
msg2 "Building custom ISO (this may take a while)...";
cd "$BUILD_DIR"

if mkarchiso -v -w "$BUILD_DIR/work" -o "$OUTPUT_DIR" "$PROFILE_DIR"; then
    msg "Custom Arch ISO built successfully!";

    # Find the generated ISO file
    ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f | head -n 1)
    if [[ -n "$ISO_FILE" ]]; then
        ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
        msg2 "ISO file: $ISO_FILE";
        msg2 "Size: $ISO_SIZE";

        # Calculate checksums
        msg2 "Calculating checksums...";
        cd "$OUTPUT_DIR"
        sha256sum "$(basename "$ISO_FILE")" > "$(basename "$ISO_FILE").sha256"
        md5sum "$(basename "$ISO_FILE")" > "$(basename "$ISO_FILE").md5"

        msg2 "Checksum files created:";
        msg2 "  - $(basename "$ISO_FILE").sha256";
        msg2 "  - $(basename "$ISO_FILE").md5";
    else
        warning "Could not find generated ISO file in $OUTPUT_DIR";
    fi

    msg2 "Build completed successfully!";
    msg2 "Files available in: $OUTPUT_DIR";

else
    error "ISO build failed!";
    exit 1;
fi

# Clean up build directory
msg2 "Cleaning up build directory...";
rm -rf "$BUILD_DIR"

msg "Custom Arch ISO creation completed!";
msg2 "Features included:";
msg2 "  - Fish shell as default with auto-tmux";
msg2 "  - SSH daemon enabled and auto-started";
msg2 "  - Complete ops-scripts directory at /root/scripts/";
msg2 "  - NFS mount script at ./mount-nfs";
msg2 "  - Email setup script at ./setup-email";
msg2 "  - NFS, tmux, msmtp, neovim pre-installed";

if [[ -n "$ISO_FILE" ]]; then
    msg2 "To use the ISO:";
    msg2 "  1. Flash to USB: dd if='$ISO_FILE' of=/dev/sdX bs=4M status=progress";
    msg2 "  2. Boot from USB";
    msg2 "  3. Run: ./mount-nfs (to mount backups)";
fi
