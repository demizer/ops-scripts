#!/bin/bash

# User configuration script for motorhead
# Creates jesusa user with same settings as host system

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Pre-populated configuration from host system
MOUNT_ROOT="${MOUNT_ROOT:-/mnt/root}"
USERNAME="jesusa"
HOST_UID=1000
HOST_GID=1000
HOST_GROUPS="jesusa,uucp,users,docker,dialout,bigdata,wheel"
HOST_SHELL="/usr/bin/fish"
HOST_GECOS="Jesus Alvarez"

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure jesusa user in the new system with host system settings

OPTIONS:
    -h, --help              Show this help message
    -m, --mount-root PATH   Set mount root (default: /mnt/root)

EXAMPLES:
    $0
    $0 -m /mnt/root

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help)
            show_help
            exit 0
            ;;
        -m | --mount-root)
            MOUNT_ROOT="$2"
            shift 2
            ;;
        *)
            err "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ "$(id -u)" != "0" ]]; then
    err "This script must be run as root"
fi

# Check if mount root exists
if [[ ! -d "$MOUNT_ROOT" ]]; then
    err "Mount root directory $MOUNT_ROOT does not exist"
fi

msg "Configuring user $USERNAME with pre-configured host system settings"
msg "UID=$HOST_UID, GID=$HOST_GID, Shell=$HOST_SHELL"
msg "Groups: $HOST_GROUPS"

# Create user in chroot with same settings
msg "Creating user $USERNAME in new system..."

# Check if user already exists
if arch-chroot "$MOUNT_ROOT" id "$USERNAME" > /dev/null 2>&1; then
    msg "User $USERNAME already exists, updating settings..."
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" usermod -u "$HOST_UID" -g "$HOST_GID" -s "$HOST_SHELL" -c "$HOST_GECOS" "$USERNAME" || {
        warn "Failed to update user settings"
    }
else
    msg "Creating user $USERNAME..."
    
    # First ensure the primary group exists
    msg "Checking if group with GID $HOST_GID exists..."
    if ! arch-chroot "$MOUNT_ROOT" getent group "$HOST_GID" > /dev/null 2>&1; then
        msg "Creating group with GID $HOST_GID for user $USERNAME..."
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" groupadd -g "$HOST_GID" "$USERNAME" || {
            warn "Failed to create primary group, will use default group creation"
        }
    fi
    
    # Create user with same UID, GID, shell, and GECOS
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" useradd -u "$HOST_UID" -g "$HOST_GID" -m -s "$HOST_SHELL" -c "$HOST_GECOS" "$USERNAME" || {
        # If user creation fails (maybe due to UID conflict), create with default settings
        warn "Failed to create user with exact UID/GID, using defaults"
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" useradd -m -G wheel -s "$HOST_SHELL" "$USERNAME" || {
            err "Failed to create user $USERNAME"
        }
    }
fi

# Add user to groups
msg "Adding user to groups..."
IFS=',' read -ra GROUP_ARRAY <<< "$HOST_GROUPS"
for group in "${GROUP_ARRAY[@]}"; do
    # Skip primary group and add others
    if [[ "$group" != "$USERNAME" ]]; then
        # Check if group exists before trying to create it
        if ! arch-chroot "$MOUNT_ROOT" getent group "$group" > /dev/null 2>&1; then
            msg "Creating group $group..."
            run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" groupadd "$group" || {
                warn "Failed to create group $group"
                continue
            }
        fi

        # Add user to group
        msg "Adding user $USERNAME to group $group..."
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" usermod -a -G "$group" "$USERNAME" || {
            warn "Failed to add user $USERNAME to group $group"
        }
    fi
done

# Set password interactively
msg "Setting password for user $USERNAME..."
msg "You will be prompted to enter a password for the $USERNAME user"
run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" passwd "$USERNAME"

# Set ownership of home directory
# Use numeric UID:GID since group name might not match username
run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" chown -R "$HOST_UID:$HOST_GID" "/home/$USERNAME"

# Setup neovim configuration for both root and jesusa
msg "Setting up neovim configuration..."

# Setup for root user
msg "Configuring neovim for root user..."
run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" mkdir -p /root/.config/nvim || {
    warn "Failed to create /root/.config/nvim directory"
}

# Copy nvim.lua as init.lua for root
if [[ -f "$SCRIPT_DIR/../../nvim.lua" ]]; then
    cp "$SCRIPT_DIR/../../nvim.lua" "$MOUNT_ROOT/root/.config/nvim/init.lua" || {
        warn "Failed to copy nvim configuration for root"
    }
    msg "Neovim configuration copied for root user"
else
    warn "nvim.lua not found at $SCRIPT_DIR/../../nvim.lua"
fi

# Setup for jesusa user
msg "Configuring neovim for $USERNAME user..."
run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" mkdir -p "/home/$USERNAME/.config/nvim" || {
    warn "Failed to create /home/$USERNAME/.config/nvim directory"
}

# Copy nvim.lua as init.lua for jesusa
if [[ -f "$SCRIPT_DIR/../../nvim.lua" ]]; then
    cp "$SCRIPT_DIR/../../nvim.lua" "$MOUNT_ROOT/home/$USERNAME/.config/nvim/init.lua" || {
        warn "Failed to copy nvim configuration for $USERNAME"
    }
    # Set proper ownership for jesusa's config
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" chown -R "$HOST_UID:$HOST_GID" "/home/$USERNAME/.config" || {
        warn "Failed to set ownership of neovim config for $USERNAME"
    }
    msg "Neovim configuration copied for $USERNAME user"
else
    warn "nvim.lua not found at $SCRIPT_DIR/../../nvim.lua"
fi

msg "User $USERNAME configured successfully"

exit 0
