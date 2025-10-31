# Zigbeeween Project - Development Guide

## Flashing and Development Workflow

### Prerequisites
- ESP-IDF v5.5.1 installed and environment sourced
- `just` command runner installed
- Device connected via USB

### Standard Build and Flash Sequence

#### Initial Build (or after sdkconfig changes)
```bash
# 1. Clean build artifacts AND sdkconfig
just clean

# 2. Erase flash completely (REQUIRED: specify device path)
just erase /dev/ttyACM0

# 3. Build the project
just build

# 4. Flash to device (NO button pressing required!)
just flash /dev/ttyACM0

# 5. Monitor serial output
just monitor /dev/ttyACM0
```

**Important Notes:**
- You MUST specify the device path explicitly (e.g., `/dev/ttyACM0`). The Justfiles no longer auto-detect devices.
- `just clean` now removes BOTH `build/` and `sdkconfig` to ensure a completely fresh build with current settings from `sdkconfig.defaults`.

#### Quick Rebuild (no sdkconfig changes)
If you're just modifying code and haven't changed `sdkconfig.defaults` or run `menuconfig`:
- Press `Control+T` then `Control+F` in the monitor to rebuild and flash
- This is much faster than the full sequence above

#### When to Use Full Clean Build
You MUST do a full clean build (`just clean` + rebuild) when:
- Changing `sdkconfig.defaults` settings
- Running `just menuconfig` and modifying Kconfig options
- Switching between different ESP-IDF versions
- Build errors that seem unrelated to your code changes
- After updating managed component dependencies

### Finding Your Device Path

To find which device is which:
```bash
# List all USB serial devices
ls -l /dev/ttyACM*

# Watch devices as you plug them in
watch -n 0.5 'ls -l /dev/ttyACM* 2>/dev/null'
```

Common device paths:
- `/dev/ttyACM0` - First USB serial device
- `/dev/ttyACM1` - Second USB serial device
- `/dev/ttyACM2` - Third USB serial device

**Tip**: Plug devices in one at a time to identify which path belongs to which device.

### Why No Button Pressing?

The XIAO ESP32-C6 has extremely tiny BOOT and RESET buttons that are hard to press. The Justfile is configured to automatically put the device into bootloader mode using `esptool.py`, so you never need to manually press buttons during flashing!

### Example: Flashing the Coordinator

```bash
cd zigbee_border_gateway
just clean
just erase /dev/ttyACM0 /dev/ttyACM1  # gateway coordinator
just build
just flash-xiaoc6 /dev/ttyACM1
just monitor-xiaoc6 /dev/ttyACM1
```

### Troubleshooting

#### Flash Failed
- Check USB connection
- Try a different USB cable
- Verify device appears in `/dev/ttyACM*`
- Check permissions: `sudo usermod -a -G dialout $USER` (then logout/login)

#### Wrong Device Path
- Disconnect other ESP32 devices
- Verify device path with `ls -l /dev/ttyACM*`
- Plug devices in one at a time to identify paths

#### Build Errors After Config Changes
```bash
just clean  # Now removes both build/ and sdkconfig
just build
```

#### Managed Components Corrupted
```bash
rm -rf managed_components dependencies.lock
just build  # Will re-download components
```

## Project Architecture

### System Overview
```
Internet
   ↓
TinyS3 (ESP32-S3) WiFi/HTTP Controller
   ├── PIR Motion Sensor
   ├── OLED Display (128x32 I2C)
   └── UART → XIAO C6 (ESP32-C6) Zigbee Coordinator
                ├── Zigbee Network (Channel 15)
                ├── Custom Time Sync Cluster (0xFC00)
                ├── Custom Trigger Request Cluster (0xFC01)
                └── Zigbee End Devices:
                    ├── Haunted Pumpkin Scarecrow (Relay)
                    └── RIP Tombstone (NeoPixel LEDs + PIR)
```

### Communication Flow

#### Time Synchronization
1. TinyS3 gets time from NTP (192.168.5.1)
2. TinyS3 sends time to coordinator via UART
3. Coordinator broadcasts time to all end devices via Zigbee custom cluster (0xFC00)
4. End devices update their clocks and manage sleep schedules

#### Trigger Flow (from RIP Tombstone PIR)
1. RIP Tombstone PIR detects motion
2. RIP Tombstone sends trigger request to coordinator via Zigbee cluster (0xFC01)
3. Coordinator receives trigger request in `zb_action_handler()`
4. Coordinator forwards trigger to Haunted Pumpkin Scarecrow via standard On/Off cluster
5. Scarecrow activates relay

This architecture means end devices don't need hardcoded IEEE addresses of other devices!

### Device Roles

**TinyS3 (ESP32-S3)**: WiFi/HTTP frontend
- Web interface on port 80
- PIR motion sensor monitoring
- OLED status display
- UART commands to coordinator
- NTP time synchronization

**XIAO C6 Coordinator**: Zigbee network manager
- Zigbee coordinator role
- Device registration and tracking
- Time sync broadcasting
- Trigger request routing
- UART communication with TinyS3

**Haunted Pumpkin Scarecrow**: Relay trigger device
- Zigbee end device (router)
- 2-channel relay control
- Time-based sleep (12am-6am)
- Standard On/Off cluster (0x0006)

**RIP Tombstone**: LED + PIR device
- Zigbee end device
- NeoPixel LED animations
- PIR motion sensor
- Multi-motion detection logic
- Time-based sleep (12am-6am)
- Trigger request cluster CLIENT (0xFC01)

## Zigbee Network Configuration

### Channel Settings
- **Primary Channel**: Channel 15 (2480 MHz)
- **Channel Mask**: `(1 << 15)` - Coordinator uses fixed channel
- **End Device Scanning**: `ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK` - End devices scan all channels to find coordinator
- **Why Channel 15**: Higher channel number reduces interference with WiFi (which typically uses channels 1, 6, 11)

**CRITICAL**: The coordinator MUST have the channel explicitly set using `esp_zb_set_primary_network_channel_set()`, otherwise it will form the network on a random channel and end devices will fail to join.

### Hardcoded Network Credentials
For production resilience, the coordinator has hardcoded network credentials so it always forms the same network after flash erase:

- **Extended PAN ID**: `0xDEADBEEFCAFEBABE` (8 bytes)
- **Network Key**: `"ZigbeeWeen2025!!"` (16 bytes: `0x5A696762656557656565...`)

These values are set in `zigbee_border_gateway/xiaoc6_zigbee/main/main.c` using:
```c
esp_zb_set_extended_pan_id(ext_pan_id);
esp_zb_secur_network_key_set(nwk_key);
esp_zb_set_primary_network_channel_set(ESP_ZB_PRIMARY_CHANNEL_MASK);
```

**WARNING**: Do NOT change these values once devices are deployed in the yard. Changing them will require re-flashing ALL devices.

## Zigbee Custom Clusters

### Time Sync Cluster (0xFC00)
- **Cluster ID**: `0xFC00`
- **Attribute ID**: `0x0000`
- **Type**: `ESP_ZB_ZCL_ATTR_TYPE_U32`
- **Purpose**: Broadcast Unix timestamp from coordinator to end devices
- **Coordinator Role**: SERVER
- **End Device Role**: CLIENT

### Trigger Request Cluster (0xFC01)
- **Cluster ID**: `0xFC01`
- **Attribute ID**: `0x0000`
- **Type**: `ESP_ZB_ZCL_ATTR_TYPE_U8`
- **Purpose**: End devices request coordinator to trigger other devices
- **Coordinator Role**: SERVER (receives requests)
- **RIP Tombstone Role**: CLIENT (sends requests)
- **Value**: `1` = trigger scarecrow

## Development Tips

### Debugging Zigbee Issues
1. Check coordinator logs for "Device announced" messages
2. Verify IEEE addresses match between code and actual devices
3. Use `esp_zb_bdb_open_network(255)` to keep network open for joining
4. Check signal strength with neighbor table iteration
5. **If devices won't join after erase/reflash**: Power cycle the coordinator to reset the permit join state
6. **If only some devices join**: Try power cycling end devices - they may need a fresh boot to properly scan channels

### Adding New Zigbee End Devices
1. Add IEEE address to coordinator's hardcoded list
2. Register device in coordinator's device tracking
3. Add to TinyS3 web interface
4. Implement custom cluster handlers if needed

### Serial Monitor Tips
- Press `Ctrl+]` to exit monitor
- Press `Ctrl+T` + `Ctrl+H` for help menu
- Press `Ctrl+T` + `Ctrl+F` to rebuild and flash
- Use `ESP_LOGI()` with unique tags for better log filtering

### Managing Multiple Devices
Use separate terminal windows for each device:
```bash
# Terminal 1: Coordinator
cd zigbee_border_gateway/xiaoc6_zigbee && just monitor coord

# Terminal 2: Gateway
cd zigbee_border_gateway/tinys3d_wifi && just monitor gateway

# Terminal 3: Scarecrow
cd zigbee_haunted_pumpkin_scarecrow && just monitor scarecrow

# Terminal 4: RIP Tombstone
cd zigbee_rip_tombstone && just monitor rip
```
