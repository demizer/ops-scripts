#!/bin/bash
# Find TinyC6 ESP32-C6 device using lsusb output and sysfs

set -u

# Define expected USB device ID for Espressif USB JTAG/serial debug unit
ESPRESSIF_VID="303a"
ESPRESSIF_PID="1001"

# Check if device exists using lsusb
if ! lsusb | grep -q "$ESPRESSIF_VID:$ESPRESSIF_PID"; then
    echo "ERROR: TinyC6 device not found (ID $ESPRESSIF_VID:$ESPRESSIF_PID)" >&2
    exit 1
fi

# Search sysfs for the device and find its tty device
TTY_DEVICE=""
for SYSDEV in /sys/bus/usb/devices/*; do
    if [ -f "$SYSDEV/idVendor" ] && [ -f "$SYSDEV/idProduct" ]; then
        VID=$(cat "$SYSDEV/idVendor" 2>/dev/null)
        PID=$(cat "$SYSDEV/idProduct" 2>/dev/null)

        if [ "$VID" = "$ESPRESSIF_VID" ] && [ "$PID" = "$ESPRESSIF_PID" ]; then
            # Look for tty subdirectory
            for TTY_DIR in "$SYSDEV"/*/tty/*; do
                if [ -d "$TTY_DIR" ] || [ -L "$TTY_DIR" ]; then
                    TTY_NAME=$(basename "$TTY_DIR")
                    TTY_DEVICE="/dev/$TTY_NAME"
                    break 2
                fi
            done
        fi
    fi
done

# Check if device was found
if [ -z "$TTY_DEVICE" ]; then
    echo "ERROR: Could not find TTY device for Espressif device $ESPRESSIF_VID:$ESPRESSIF_PID" >&2
    exit 1
fi

# Verify device exists and is accessible
if [ ! -c "$TTY_DEVICE" ]; then
    echo "ERROR: Device $TTY_DEVICE does not exist or is not a character device" >&2
    exit 1
fi

if ! test -r "$TTY_DEVICE" || ! test -w "$TTY_DEVICE"; then
    echo "WARNING: Device $TTY_DEVICE may not be accessible (check permissions)" >&2
fi

# Output the device path for use by other scripts
echo "$TTY_DEVICE"