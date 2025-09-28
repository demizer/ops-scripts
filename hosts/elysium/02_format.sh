#!/bin/bash

# Format motorhead partitions

# Load common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib.sh"

# Parse command line arguments
FORCE=false

DEVICE="/dev/disk/by-id/nvme-CT4000T700SSD3_2449E9984FD9"

while [[ $# -gt 0 ]]; do
    case $1 in
        -f | --force)
            FORCE=true
            shift
            ;;
        -h | --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Format partitions for motorhead"
            echo ""
            echo "OPTIONS:"
            echo "    -f, --force    Force overwrite existing filesystems"
            echo "    -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Wait for partition devices to appear and find the correct device path
echo "Waiting for partition devices to appear..."
run_cmd_no_subshell sleep 3
run_cmd_no_subshell partprobe "$DEVICE"
run_cmd_no_subshell sleep 2

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

# Wait for partition devices to be available
for part in "$PART1" "$PART2" "$PART3" "$PART4" "$PART5"; do
    timeout=10
    while [[ $timeout -gt 0 && ! -e "$part" ]]; do
        echo "Waiting for $part to appear..."
        sleep 1
        ((timeout--))
    done
    if [[ ! -e "$part" ]]; then
        echo "ERROR: Partition $part not found after waiting"
        exit 1
    fi
done

# Set force flags based on command line option
if [[ "$FORCE" == true ]]; then
    MKSWAP_FORCE="-f"
    MKFS_EXT4_FORCE="-F"
    echo "Force mode enabled - will overwrite existing filesystems"

    # Unmount any mounted partitions first
    echo "Checking for mounted partitions to unmount..."
    for part in "$PART1" "$PART2" "$PART3" "$PART4" "$PART5"; do
        if mountpoint -q "$part" 2> /dev/null || mount | grep -q "^$part "; then
            echo "Unmounting $part..."
            umount -R "$part" 2> /dev/null || {
                echo "Warning: Failed to unmount $part, trying lazy unmount..."
                umount -l "$part" 2> /dev/null || {
                    echo "Warning: Could not unmount $part"
                }
            }
        fi
    done

    # Also check for bind mounts or anything mounted under /mnt/root
    if mountpoint -q /mnt/root 2> /dev/null; then
        echo "Unmounting /mnt/root and all submounts..."
        umount -R /mnt/root 2> /dev/null || {
            echo "Warning: Failed to unmount /mnt/root, trying lazy unmount..."
            umount -l /mnt/root 2> /dev/null || {
                echo "Warning: Could not unmount /mnt/root"
            }
        }
    fi

    # Give the system a moment to process the unmounts
    sleep 2
else
    MKSWAP_FORCE=""
    MKFS_EXT4_FORCE=""
fi

# Format EFI partition (FAT32)
run_cmd_no_subshell mkfs.fat -F32 -n "EFI" "$PART1" || exit 1

# Format swap partition
run_cmd_no_subshell mkswap $MKSWAP_FORCE -L "SWAP" "$PART2" || exit 1

# Format root partition (ext4)
run_cmd_no_subshell mkfs.ext4 $MKFS_EXT4_FORCE -L "ROOT" "$PART3" || exit 1

# Format var partition (ext4)
run_cmd_no_subshell mkfs.ext4 $MKFS_EXT4_FORCE -L "VAR" "$PART4" || exit 1

# Format home partition (ext4)
run_cmd_no_subshell mkfs.ext4 $MKFS_EXT4_FORCE -L "HOME" "$PART5" || exit 1

echo "All partitions formatted"
