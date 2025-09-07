#!/bin/bash

# NFS Mount Script for Arch Linux Live ISO
# Mounts the NFS backups share from nas.alvaone.net

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

msg "Mounting NFS backups share"

# Install nfs-utils if not present
msg2 "Installing nfs-utils package..."
if ! pacman -Q nfs-utils &> /dev/null; then
    pacman -S --noconfirm nfs-utils
else
    msg2 "nfs-utils already installed"
fi

# Mount NFS share
msg2 "Mounting NFS backups share..."
NFS_MOUNT="/mnt/backups"
NFS_SERVER="nas.alvaone.net:/mnt/bigdata/backups"

if mountpoint -q "$NFS_MOUNT"; then
    msg2 "NFS share already mounted at $NFS_MOUNT"
else
    mount --mkdir -o _netdev,noatime,nodiratime,rsize=131072,wsize=131072,timeo=600 "$NFS_SERVER" "$NFS_MOUNT"
    if mountpoint -q "$NFS_MOUNT"; then
        msg2 "NFS share mounted successfully at $NFS_MOUNT"
    else
        error "Failed to mount NFS share"
        exit 1
    fi
fi

msg "NFS mount completed successfully at $NFS_MOUNT"
