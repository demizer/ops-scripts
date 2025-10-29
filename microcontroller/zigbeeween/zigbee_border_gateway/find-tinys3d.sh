#!/usr/bin/env bash
# Find TinyS3 ESP32-S3 device

set -euo pipefail

echo "🔍 Looking for TinyS3 ESP32-S3..." >&2
echo "" >&2
echo "📌 Connect TinyS3 via USB cable" >&2
echo "" >&2
echo "⚠️  Put device in bootloader mode:" >&2
echo "   1. Hold BOOT button (labeled '0' or 'BOOT')" >&2
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
    # Check for ESP32-S3 by USB vendor/product ID or serial description
    for device in /dev/ttyACM* /dev/ttyUSB*; do
        if [ -e "$device" ]; then
            # Try to identify as ESP32-S3
            if udevadm info "$device" 2>/dev/null | grep -qi "esp32s3\|303a:1001\|tinys3\|unexpected.*maker"; then
                echo "✓ TinyS3 ESP32-S3 found at: $device" >&2
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

echo "❌ Timeout: TinyS3 ESP32-S3 not found after ${TIMEOUT} seconds" >&2
echo "   Make sure device is in bootloader mode" >&2
exit 1
