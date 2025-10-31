# Zigbeeween - Halloween Decoration Zigbee Control System

A distributed Halloween decoration control system using ESP32 microcontrollers with WiFi and Zigbee networking.

## System Architecture

```
Internet
   ↓
TinyS3 (ESP32-S3) - WiFi/HTTP/PIR
   ↓ UART
XIAO C6 (ESP32-C6) - Zigbee Coordinator
   ↓ Zigbee (Channel 15)
   ├── Haunted Pumpkin Scarecrow (End Device - Relay)
   └── RIP Tombstone (End Device - LEDs + PIR)
```

## Components

### Border Gateway (`zigbee_border_gateway/`)
Dual-microcontroller gateway providing WiFi web interface and Zigbee coordination.

**TinyS3 (ESP32-S3)**:
- Web interface with manual trigger controls
- PIR motion sensor
- OLED status display
- NTP time synchronization
- UART communication to Zigbee coordinator

**XIAO C6 (ESP32-C6)**:
- Zigbee coordinator
- Device registration and tracking
- Time sync broadcasting
- Trigger request routing

### Haunted Pumpkin Scarecrow (`zigbee_haunted_pumpkin_scarecrow/`)
- Zigbee end device with relay control
- 2-channel relay module (5V)
- Time-synchronized sleep schedule (12am-6am)
- Responds to Zigbee On/Off commands

### RIP Tombstone (`zigbee_rip_tombstone/`)
- Zigbee end device with NeoPixel LEDs
- PIR motion sensor
- Multi-motion detection (single = red blink, 3 in 90s = rainbow)
- Triggers scarecrow via coordinator (no hardcoded addresses!)
- Time-synchronized sleep schedule (12am-6am)
- 2-minute cooldown between triggers

## Features

- **Web Interface**: Control all decorations from any device on WiFi
- **Motion Detection**: Dual PIR sensors (gateway + RIP tombstone)
- **Time Synchronization**: NTP → WiFi → Zigbee custom cluster
- **Sleep Scheduling**: Automatic power saving 12am-6am
- **Event Logging**: Track all triggers and device status
- **Signal Monitoring**: Display Zigbee LQI and RSSI
- **Custom Zigbee Clusters**:
  - Time Sync (0xFC00) - Broadcast time to end devices
  - Trigger Request (0xFC01) - End devices request coordinator actions

## Quick Start

### 1. Set up ESP-IDF
```bash
. $HOME/esp/esp-idf/export.sh
```

### 2. Build and Flash Devices

See [CLAUDE.md](CLAUDE.md) for detailed flashing instructions. Quick reference:

```bash
# Find your device paths
ls -l /dev/ttyACM*

# Clean build and flash sequence (explicit device paths required)
just clean
just erase /dev/ttyACM0
just build
just flash /dev/ttyACM0
just monitor /dev/ttyACM0

# Quick rebuild (no sdkconfig changes)
# Press Control+T + Control+F in monitor
```

**Important**: You MUST specify device paths explicitly (e.g., `/dev/ttyACM0`). Auto-detection has been removed.

### 3. Start in Order

1. **Flash Coordinator** first:
   ```bash
   cd zigbee_border_gateway
   just clean
   just erase /dev/ttyACM0 /dev/ttyACM1  # gateway coordinator
   just build
   just flash-xiaoc6 /dev/ttyACM1
   ```

2. **Flash Gateway** (TinyS3):
   ```bash
   just flash-tinys3 /dev/ttyACM0
   ```

3. **Flash End Devices**:
   ```bash
   cd ../zigbee_haunted_pumpkin_scarecrow
   just clean && just erase /dev/ttyACM0 && just build && just flash /dev/ttyACM0

   cd ../zigbee_rip_tombstone
   just clean && just erase /dev/ttyACM0 && just build && just flash /dev/ttyACM0
   ```

### 4. Access Web Interface

Find the gateway IP address in the TinyS3 serial monitor, then open:
```
http://<gateway-ip>/
```

## Hardware Requirements

### Border Gateway
- 1x TinyS3 (ESP32-S3) with external antenna
- 1x XIAO ESP32-C6
- 1x PIR motion sensor (HC-SR501 or similar)
- 1x SSD1306 OLED display (128x32, I2C)
- UART wiring between TinyS3 and XIAO C6

### Per Decoration
- 1x XIAO ESP32-C6
- Power supply (USB 5V or battery)
- Decoration-specific hardware:
  - **Scarecrow**: 2-channel 5V relay module
  - **RIP Tombstone**: WS2812 NeoPixel strip + PIR sensor

## Pin Connections

See individual project READMEs:
- [Border Gateway Pins](zigbee_border_gateway/README.md)
- [Scarecrow Pins](zigbee_haunted_pumpkin_scarecrow/README.md)
- [RIP Tombstone Pins](zigbee_rip_tombstone/README.md)

## Development Workflow

### Standard Build/Flash
```bash
just clean             # Clean build artifacts
just erase /dev/ttyACM0 # Erase flash (explicit path required)
just build             # Build project
just flash /dev/ttyACM0 # Flash to device (no button pressing!)
just monitor /dev/ttyACM0 # Monitor serial output
```

### Quick Iteration
When only changing code (not sdkconfig):
- In monitor: `Control+T` + `Control+F` to rebuild and flash

### When to Clean Build
Full clean required when:
- Modifying `sdkconfig.defaults`
- Running `menuconfig`
- Changing managed component versions
- Build errors after pulling code changes

## Configuration

### WiFi Settings (TinyS3)
Edit `zigbee_border_gateway/tinys3d_wifi/sdkconfig.defaults`:
```
CONFIG_ESP_WIFI_SSID="YourSSID"
CONFIG_ESP_WIFI_PASSWORD="YourPassword"
```

### Zigbee Channel
Default: Channel 15 (2.4GHz @ 2480 MHz)

To change, edit in each project's `main.c`:
```c
#define ZIGBEE_CHANNEL 15
```

### Device IEEE Addresses
Add new devices to `zigbee_border_gateway/xiaoc6_zigbee/main/main.c`:
```c
#define NEW_DEVICE_IEEE 0x9888e0fffe7f1234ULL
```

## Troubleshooting

### Devices Won't Join Zigbee Network
1. Check coordinator is running and formed network
2. Verify `esp_zb_bdb_open_network(255)` called in coordinator
3. Check IEEE addresses match between code and devices
4. Power-cycle end devices
5. Monitor coordinator logs for "Device announced" messages

### Time Not Syncing
1. Check TinyS3 has NTP sync (should log time on startup)
2. Verify coordinator receives time via UART
3. Check coordinator broadcasts time every 5 minutes
4. Monitor end device logs for time sync messages

### RIP Tombstone Won't Trigger Scarecrow
1. Verify both devices connected to coordinator
2. Check coordinator has trigger request cluster (0xFC01) as SERVER
3. Check RIP tombstone has trigger request cluster as CLIENT
4. Monitor coordinator logs for "Received trigger request" messages

### Flash Permission Denied
```bash
sudo usermod -a -G dialout $USER
# Then logout and login
```

## Project Structure

```
zigbeeween/
├── CLAUDE.md                          # Development guide (this file)
├── README.md                          # Project overview
├── zigbee_border_gateway/
│   ├── tinys3d_wifi/                  # ESP32-S3 WiFi controller
│   │   ├── main/main.c
│   │   ├── Justfile
│   │   └── README.md
│   ├── xiaoc6_zigbee/                 # ESP32-C6 Zigbee coordinator
│   │   ├── main/main.c
│   │   ├── Justfile
│   │   └── README.md
│   └── README.md
├── zigbee_haunted_pumpkin_scarecrow/  # Relay end device
│   ├── main/main.c
│   ├── Justfile
│   └── README.md
└── zigbee_rip_tombstone/              # LED + PIR end device
    ├── main/main.c
    ├── Justfile
    └── README.md
```

## Technical Details

### Zigbee Custom Clusters

**Time Sync Cluster (0xFC00)**:
- Coordinator broadcasts Unix timestamps
- End devices update clocks and sleep schedules
- Eliminates need for RTC chips

**Trigger Request Cluster (0xFC01)**:
- End devices send trigger requests to coordinator
- Coordinator routes to target devices
- Avoids hardcoding IEEE addresses on end devices

### Communication Protocols

**UART (TinyS3 ↔ XIAO C6)**:
- Baud: 115200
- Protocol: Framed messages (0xAA ... 0x55)
- Commands: Trigger, Status Request, Time Sync, Device Events

**Zigbee**:
- Channel: 15 (2480 MHz)
- Network type: Coordinator + End Devices/Routers
- Standard clusters: On/Off (0x0006), Basic (0x0000), Identify (0x0003)
- Custom clusters: Time Sync (0xFC00), Trigger Request (0xFC01)

### Power Management

All end devices:
- Active: ~80-100mA (Zigbee on)
- Sleep: ~10-20µA (coordinator maintains time)
- Schedule: Sleep 12am-6am (saves ~500mAh/night)
- Wake trigger: Deep sleep timer

## License

See LICENSE file.

## Contributing

1. Test all devices after changes
2. Document new features in READMEs
3. Update CLAUDE.md for workflow changes
4. Follow existing code style (no emoji in code comments)

## Support

Check individual project READMEs for component-specific documentation and troubleshooting.
