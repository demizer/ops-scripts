#!/bin/bash

# Group configuration script for motorhead
# Creates bigdata group with specific GID

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Pre-populated configuration
MOUNT_ROOT="${MOUNT_ROOT:-/mnt/root}"
BIGDATA_GID=5000

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure bigdata group in the new system

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

msg "Configuring bigdata group"

# Create bigdata group with specific GID
msg "Checking if bigdata group exists..."
existing_gid=$(arch-chroot "$MOUNT_ROOT" getent group bigdata 2> /dev/null | cut -d: -f3)

if [[ -n "$existing_gid" ]]; then
    if [[ "$existing_gid" != "$BIGDATA_GID" ]]; then
        warn "Group bigdata exists but has GID $existing_gid instead of $BIGDATA_GID"
        msg "Modifying bigdata group to use GID $BIGDATA_GID..."
        run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" groupmod -g "$BIGDATA_GID" bigdata
    else
        msg "Group bigdata already exists with correct GID $BIGDATA_GID"
    fi
else
    msg "Creating bigdata group with GID $BIGDATA_GID..."
    run_cmd_no_subshell arch-chroot "$MOUNT_ROOT" groupadd -g "$BIGDATA_GID" bigdata
fi

msg "Bigdata group configuration completed"

exit 0
