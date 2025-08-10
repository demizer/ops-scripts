#!/bin/bash

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

DEVICE="/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7L9NJ0Y438532K"

# Get the real device path
REAL_DEVICE=$(readlink -f "$DEVICE" 2>/dev/null || echo "$DEVICE")
echo "Unmounting any existing partitions on $REAL_DEVICE..."

# Find all partitions on this device and unmount them
for partition in $(lsblk -nr -o NAME "$REAL_DEVICE" 2>/dev/null | tail -n +2); do
    partition_path="/dev/$partition"
    if mountpoint -q "$partition_path" 2>/dev/null; then
        echo "Unmounting $partition_path"
        run_cmd_no_subshell umount "$partition_path" || run_cmd_no_subshell umount -f "$partition_path" || true
    fi
done

# Turn off any swap partitions on this device
swapon --show=NAME --noheadings 2>/dev/null | grep "$REAL_DEVICE" | while read -r swap_part; do
    echo "Disabling swap on $swap_part"
    run_cmd_no_subshell swapoff "$swap_part" || true
done

# Wait for unmounts to complete
run_cmd_no_subshell sleep 2

# Clear existing partition table and create new GPT
run_cmd_no_subshell sgdisk --zap-all "$DEVICE" || exit 1

# Create partitions
run_cmd_no_subshell sgdisk -n 1:0:+1500M -t 1:ef00 -c 1:"EFI System" "$DEVICE" || exit 1
run_cmd_no_subshell sgdisk -n 2:0:+40G -t 2:8200 -c 2:"SWAP" "$DEVICE" || exit 1
run_cmd_no_subshell sgdisk -n 3:0:+50G -t 3:8300 -c 3:"Root" "$DEVICE" || exit 1
run_cmd_no_subshell sgdisk -n 4:0:+500G -t 4:8300 -c 4:"Var" "$DEVICE" || exit 1
run_cmd_no_subshell sgdisk -n 5:0:0 -t 5:8300 -c 5:"Home" "$DEVICE" || exit 1

# Print final partition table
run_cmd_no_subshell sgdisk -p "$DEVICE" || exit 1
