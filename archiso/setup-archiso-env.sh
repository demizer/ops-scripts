#!/bin/bash

# Arch Linux Live ISO Environment Setup Script
# 1. Activates SSH daemon
# 2. Mounts NFS backups share
# 3. Calls setup email script
# 4. Starts tmux session

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

msg "Setting up Arch Linux Live ISO environment";

# 1. Activate SSH daemon
msg2 "Starting SSH daemon...";
if systemctl is-active --quiet sshd; then
    msg2 "SSH daemon is already running";
else
    systemctl start sshd
    if systemctl is-active --quiet sshd; then
        msg2 "SSH daemon started successfully";
    else
        error "Failed to start SSH daemon";
        exit 1;
    fi
fi

# Display SSH connection info
IP_ADDR=$(ip route get 1.1.1.1 | awk '{print $7}' | head -n1)
if [[ -n "$IP_ADDR" ]]; then
    msg2 "SSH available at: ssh root@${IP_ADDR}";
else
    warning "Could not determine IP address for SSH connection";
fi

# 2. Mount NFS backups share
msg2 "Installing nfs-utils package...";
if ! pacman -Q nfs-utils &>/dev/null; then
    pacman -S --noconfirm nfs-utils
else
    msg2 "nfs-utils already installed";
fi

msg2 "Mounting NFS backups share...";
NFS_MOUNT="/mnt/backups"
NFS_SERVER="nas.alvaone.net:/mnt/bigdata/backups"

if mountpoint -q "$NFS_MOUNT"; then
    msg2 "NFS share already mounted at $NFS_MOUNT";
else
    mount --mkdir -o noauto,noatime,nodiratime,proto=tcp,rsize=131072,wsize=131072,hard,intr,timeo=600,retrans=5 "$NFS_SERVER" "$NFS_MOUNT"
    if mountpoint -q "$NFS_MOUNT"; then
        msg2 "NFS share mounted successfully at $NFS_MOUNT";
    else
        error "Failed to mount NFS share";
        exit 1;
    fi
fi

# 3. Call setup email script
msg2 "Setting up email configuration...";
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMAIL_SCRIPT="$SCRIPT_DIR/setup-sendmail-bridge.sh"

if [[ -f "$EMAIL_SCRIPT" ]]; then
    bash "$EMAIL_SCRIPT"
    if [[ $? -eq 0 ]]; then
        msg2 "Email setup completed successfully";
    else
        warning "Email setup encountered issues (continuing anyway)";
    fi
else
    warning "Email setup script not found at $EMAIL_SCRIPT";
fi

# 4. Start tmux session
msg2 "Starting tmux session...";
SESSION_NAME="archiso-session"

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    msg2 "Installing tmux...";
    pacman -S --noconfirm tmux
fi

# Kill existing session if it exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    msg2 "Killing existing tmux session '$SESSION_NAME'";
    tmux kill-session -t "$SESSION_NAME"
fi

# Create new session in detached mode
tmux new-session -d -s "$SESSION_NAME"

msg "Arch Linux Live ISO environment setup completed!";
msg2 "Services started:";
msg2 "  - SSH daemon (available at: ssh root@${IP_ADDR:-<unknown-ip>})";
msg2 "  - NFS backups share mounted at $NFS_MOUNT";
msg2 "  - Email configuration applied";
msg2 "  - Tmux session '$SESSION_NAME' created";

msg2 "To connect to the tmux session, run:";
msg2 "tmux attach-session -t $SESSION_NAME";

# Offer to attach immediately
echo -n "Attach to tmux session now? [Y/n]: "
read -r response
if [[ "$response" =~ ^[Nn]$ ]]; then
    msg2 "Session ready. Connect later with: tmux attach-session -t $SESSION_NAME";
else
    msg2 "Attaching to tmux session...";
    exec tmux attach-session -t "$SESSION_NAME"
fi