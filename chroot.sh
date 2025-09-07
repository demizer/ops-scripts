#!/usr/bin/env bash

export TERM=xterm

# Parse command line arguments
USB_DEVICE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            USB_DEVICE="$2"
            shift 2
            ;;
        -h | --help)
            echo "Usage: $0 [--device DEVICE]"
            echo "  --device DEVICE    Use specific device (e.g., /dev/sda)"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            exit 1
            ;;
    esac
done

# Line 4: Get the USB device - either from arg or currently mounted to /mnt/usb-tools
if [[ -z "$USB_DEVICE" ]]; then
    USB_DEVICE=$(findmnt -n -o SOURCE /mnt/usb-tools | sed 's/[0-9]*$//')
    echo "Line 4: Auto-detected USB_DEVICE=$USB_DEVICE"
else
    echo "Line 4: Using provided USB_DEVICE=$USB_DEVICE"
fi

# Line 7: Check if we found a USB device
if [[ -z "$USB_DEVICE" ]]; then
    echo "Error: No device found mounted at /mnt/usb-tools and no --device specified"
    exit 1
fi

# Line 12: Get the first partition of the USB device
BOOT_PARTITION="${USB_DEVICE}1"
echo "Line 12: BOOT_PARTITION=$BOOT_PARTITION"

# Line 15: Check if the boot partition exists
if [[ ! -b "$BOOT_PARTITION" ]]; then
    echo "Error: Boot partition $BOOT_PARTITION does not exist"
    exit 1
fi

# Line 20: Create /mnt/usb-tools/boot directory if it doesn't exist
if [[ ! -d /mnt/usb-tools/boot ]]; then
    echo "Line 21: mkdir -p /mnt/usb-tools/boot"
    mkdir -p /mnt/usb-tools/boot
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create /mnt/usb-tools/boot directory"
        exit 1
    fi
fi

# Line 28: Mount the first partition to /mnt/usb-tools/boot
echo "Line 29: mount $BOOT_PARTITION /mnt/usb-tools/boot"
mount "$BOOT_PARTITION" /mnt/usb-tools/boot
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to mount $BOOT_PARTITION to /mnt/usb-tools/boot"
    exit 1
fi

# Line 35: Verify the mount was successful
if ! mountpoint -q /mnt/usb-tools/boot; then
    echo "Error: /mnt/usb-tools/boot is not properly mounted"
    exit 1
fi

# Line 40: Use arch-chroot to enter the chroot environment with fish shell
echo "Line 41: arch-chroot /mnt/usb-tools /bin/fish"
arch-chroot /mnt/usb-tools /bin/fish
if [[ $? -ne 0 ]]; then
    echo "Error: arch-chroot failed"
    exit 1
fi

echo "Chroot session completed successfully"
