#!/usr/bin/env bash
# Find XIAO ESP32-C6 device

set -euo pipefail

echo "🔍 Looking for XIAO ESP32-C6..." >&2
echo "" >&2
echo "📌 Disconnect TinyS3 and connect XIAO C6 via USB cable" >&2
echo "" >&2
echo "⚠️  Put device in bootloader mode:" >&2
echo "   1. Hold BOOT button" >&2
echo "   2. Press and release RESET button" >&2
echo "   3. Release BOOT button" >&2
echo "" >&2
read -p "Press Enter when ready..." >&2
echo "" >&2
echo "⏳ Waiting for device..." >&2

# Wait for device with timeout
TIMEOUT=15
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check for ESP32-C6 by USB vendor/product ID or serial description
    for device in /dev/ttyACM* /dev/ttyUSB*; do
        if [ -e "$device" ]; then
            # Try to identify as ESP32-C6
            if udevadm info "$device" 2>/dev/null | grep -qi "esp32c6\|303a:1001"; then
                echo "✓ XIAO ESP32-C6 found at: $device" >&2
                echo "$device"
                exit 0
            fi

            # Fallback: if it's a recently connected device, assume it's correct
            if [ -c "$device" ]; then
                echo "✓ Device found at: $device" >&2
                echo "$device"
                exit 0
            fi
        fi
    done

    sleep 0.5
    ELAPSED=$((ELAPSED + 1))
done

echo "❌ Timeout: XIAO ESP32-C6 not found after ${TIMEOUT} seconds" >&2
echo "   Make sure device is in bootloader mode" >&2
exit 1
