#!/bin/bash

# Mount jesusa-fridge partitions to /mnt/root

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

DEVICE="/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7L9NJ0Y438532K"

# Try to find the actual device name (e.g., /dev/nvme0n1)
REAL_DEVICE=$(readlink -f "$DEVICE" 2> /dev/null || echo "$DEVICE")
echo "Real device: $REAL_DEVICE"

# Use the real device path for partitions
if [[ "$REAL_DEVICE" =~ nvme.*n[0-9]+$ ]]; then
    # NVMe device - partitions are like nvme0n1p1
    PART1="${REAL_DEVICE}p1"
    PART2="${REAL_DEVICE}p2"
    PART3="${REAL_DEVICE}p3"
    PART4="${REAL_DEVICE}p4"
    PART5="${REAL_DEVICE}p5"
else
    # SATA device - partitions are like sda1
    PART1="${REAL_DEVICE}1"
    PART2="${REAL_DEVICE}2"
    PART3="${REAL_DEVICE}3"
    PART4="${REAL_DEVICE}4"
    PART5="${REAL_DEVICE}5"
fi

echo "Partition devices: $PART1, $PART2, $PART3, $PART4, $PART5"

# Create mount point
run_cmd_no_subshell mkdir -p /mnt/root

# Mount root partition first
run_cmd_no_subshell mount "$PART3" /mnt/root || exit 1

# Create subdirectories
run_cmd_no_subshell mkdir -p /mnt/root/{boot,var,home}

# Mount other partitions
run_cmd_no_subshell mount "$PART1" /mnt/root/boot || exit 1
run_cmd_no_subshell mount "$PART4" /mnt/root/var || exit 1
run_cmd_no_subshell mount "$PART5" /mnt/root/home || exit 1

# Enable swap (only if not already active)
if ! swapon --show | grep -q "$PART2"; then
    run_cmd_no_subshell swapon "$PART2" || exit 1
    echo "Swap enabled on $PART2"
else
    echo "Swap already active on $PART2"
fi

echo "All partitions mounted to /mnt/root"
