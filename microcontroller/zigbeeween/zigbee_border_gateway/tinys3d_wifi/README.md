# TinyS3 ESP32-S3 WiFi/HTTP Controller

ESP-IDF project for the TinyS3 ESP32-S3 that provides WiFi web interface and UART communication with Zigbee coordinator.

## Hardware

- **Board**: TinyS3 (ESP32-S3)
- **Chip**: ESP32-S3 (Xtensa dual-core, 240MHz)
- **Memory**: 8MB PSRAM, 8MB Flash
- **Wireless**: WiFi 6 (2.4GHz + 5GHz), Bluetooth 5
- **USB**: Native USB for power and programming
- **External Antenna**: Enabled via GPIO 38

## Features

- **Web Interface**: HTTP server with device status and manual controls
- **PIR Motion Sensor**: Automatic trigger on motion detection
- **OLED Display**: 128x32 I2C status display
- **NTP Time Sync**: Accurate timekeeping (Los Angeles timezone)
- **UART to Zigbee Coordinator**: Commands and status updates
- **Event Logging**: Track triggers and device events
- **Device Status Monitoring**: Real-time Zigbee device connection status

## Pin Connections

### PIR Motion Sensor
- **VCC** → 3.3V
- **GND** → GND
- **OUT** → GPIO 1

### OLED Display (SSD1306 128x32, I2C)
- **VCC** → 3.3V
- **GND** → GND
- **SDA** → GPIO 8
- **SCL** → GPIO 9

### UART to XIAO C6 Coordinator
- **TX** → GPIO 43 (connects to XIAO C6 GPIO 17/D7 RX)
- **RX** → GPIO 44 (connects to XIAO C6 GPIO 16/D6 TX)
- **GND** → Common ground with XIAO C6

### External Antenna Control
- **GPIO 38** → Antenna select (HIGH = external, automatically configured)

## Requirements

- ESP-IDF v5.5.1 or later
- Python 3.8+
- `just` command runner
- WiFi network credentials configured in `sdkconfig.defaults`

## Configuration

### WiFi Settings

Edit `sdkconfig.defaults` before building:
```
CONFIG_ESP_WIFI_SSID="YourNetworkName"
CONFIG_ESP_WIFI_PASSWORD="YourNetworkPassword"
```

Or configure via menuconfig:
```bash
just menuconfig
# Navigate to: Example Connection Configuration
```

## Flashing and Development Workflow

### Standard Build and Flash Sequence
```bash
# 1. Clean build artifacts
just clean

# 2. Build the project (no erase needed for TinyS3)
just build

# 3. Flash to device (NO button pressing required!)
just flash gateway

# 4. Monitor serial output
just monitor gateway
```

### Quick Rebuild (no sdkconfig changes)
If you're just modifying code and haven't changed `sdkconfig.defaults`:
- In monitor: Press `Control+T` then `Control+F` to rebuild and flash
- Much faster than full clean build

### When to Use Full Clean Build
You MUST do a full clean build when:
- Changing `sdkconfig.defaults` settings (like WiFi credentials)
- Running `menuconfig` and modifying options
- Build errors that seem unrelated to code changes
- After updating managed components

**Note**: The TinyS3 has easier-to-press buttons than XIAO C6, but the Justfile still handles bootloader mode automatically!

## Available Commands

Run `just` to see all available commands:

- `just build` - Build the project
- `just flash gateway` - Flash firmware to device (auto bootloader mode)
- `just monitor gateway` - Monitor serial output
- `just dev` - Build, flash, and monitor in one command
- `just menuconfig` - Configure project settings
- `just clean` - Clean build artifacts
- `just check-device` - Check if device is connected
- `just info` - Show device information

## Web Interface

After flashing, the serial monitor will display:
```
I (xxxx) tinys3_controller: IP Address: 192.168.x.x
```

Open your browser to `http://<ip-address>/` to see:

### Status Display
- Current time (Los Angeles timezone)
- PIR motion detection status
- RIP Tombstone connection/sync/cooldown status
- Haunted Pumpkin Scarecrow connection/sync/cooldown status
- Event log (last 20 events)

### Manual Controls
- **Trigger RIP Tombstone** - Activate tombstone LEDs
- **Trigger Pumpkin Scarecrow** - Activate scarecrow relay
- **Trigger BOTH** - Activate both devices

### Auto-Refresh
The web page automatically updates every 2 seconds with latest status.

## Operation

### Startup Sequence
1. Initialize hardware (I2C, OLED, PIR, UART, antenna)
2. Connect to WiFi
3. Sync time via NTP
4. Start web server
5. Send time sync to Zigbee coordinator via UART
6. Begin PIR monitoring and status polling

### PIR Motion Detection
When motion is detected:
1. OLED displays "MOTION! DETECTED"
2. Triggers connected Zigbee devices via UART command to coordinator
3. Intelligently triggers based on which devices are connected:
   - Both connected → Trigger both
   - Only scarecrow connected → Trigger scarecrow
   - Only RIP connected → Trigger RIP
   - None connected → Log warning

### Device Status Updates
- Polls coordinator every 3 seconds via UART
- Updates connection status, time sync status, cooldown status
- Displays on web interface and logs events

## UART Protocol

Communication with XIAO C6 coordinator at 115200 baud:

### Frame Format
```
Start: 0xAA
Command: 1 byte
Data: Variable
End: 0x55
```

### Commands (TinyS3 → Coordinator)
- `0x01` - Trigger RIP tombstone
- `0x02` - Trigger haunted pumpkin scarecrow
- `0x03` - Trigger both devices
- `0x10` - Request device status
- `0x20` - Send time sync (followed by 4-byte Unix timestamp)

### Responses (Coordinator → TinyS3)
- `0x11` - Device status response (2-byte flags)
- `0x30` - Device joined notification (1-byte device ID)
- `0x31` - Device left notification (1-byte device ID)

## Troubleshooting

### WiFi Won't Connect
- Check SSID and password in `sdkconfig.defaults`
- Verify 2.4GHz network (ESP32-S3 supports both 2.4GHz and 5GHz)
- Check serial monitor for connection errors
- Ensure router is in range

### Web Interface Not Accessible
- Check serial monitor for IP address
- Verify computer on same network
- Try pinging device: `ping <ip-address>`
- Check router firewall settings

### OLED Not Displaying
- Verify I2C connections (GPIO 8 = SDA, GPIO 9 = SCL)
- Check OLED address is 0x3C
- Ensure 3.3V power to OLED
- Check I2C pull-up resistors (typically 4.7kΩ)

### PIR Not Detecting Motion
- Allow 30-60 seconds warm-up time after power-on
- Check PIR power (3.3V) and ground connections
- Verify GPIO 1 connection
- Test PIR with multimeter (should go HIGH on motion)
- Adjust sensitivity potentiometer on PIR module

### No Communication with Zigbee Coordinator
- Check UART wiring:
  - TinyS3 TX (GPIO 43) → XIAO C6 RX (GPIO 17/D7)
  - TinyS3 RX (GPIO 44) → XIAO C6 TX (GPIO 16/D6)
  - Common ground between devices
- Verify coordinator is running and powered
- Check coordinator serial output for received commands
- Monitor at 115200 baud

### Time Not Syncing
- Check WiFi connection is active
- Verify NTP server accessibility (192.168.5.1 by default)
- Check serial output for "Time synchronized" message
- Wait up to 60 seconds after boot

## Device Detection

The project uses `find-tinys3.sh` script to automatically detect the TinyS3 at `/dev/ttyACM*`.

## Customization

### Change NTP Server
Edit `main/main.c`:
```c
esp_sntp_setservername(0, "pool.ntp.org");  // Default: 192.168.5.1
```

### Change Timezone
Edit `main/main.c`:
```c
setenv("TZ", "EST5EDT,M3.2.0,M11.1.0", 1);  // Example: New York
```

Common timezones:
- Los Angeles: `PST8PDT,M3.2.0,M11.1.0` (default)
- New York: `EST5EDT,M3.2.0,M11.1.0`
- Chicago: `CST6CDT,M3.2.0,M11.1.0`
- Denver: `MST7MDT,M3.2.0,M11.1.0`
- UTC: `UTC0`

### Change PIR Pin
Edit `main/main.c`:
```c
#define PIR_PIN GPIO_NUM_1
```

### Adjust Status Poll Interval
Edit `main/main.c` in `status_request_task()`:
```c
vTaskDelay(pdMS_TO_TICKS(3000));  // Poll every 3 seconds
```

## Power Considerations

- Active mode (WiFi on): ~120-150mA
- Display adds: ~10-20mA
- PIR sensor: ~50µA (standby) to ~3mA (active)
- Total typical: ~140-180mA
- Powered via USB 5V

## System Architecture

```
Internet (NTP)
   ↓
TinyS3 (This Device)
   ├── WiFi 6 (2.4GHz/5GHz)
   ├── Web Server (HTTP)
   ├── PIR Motion Sensor
   ├── OLED Display
   └── UART (115200)
       ↓
   XIAO C6 Zigbee Coordinator
       ↓ Zigbee Network (Channel 15)
       ├── Haunted Pumpkin Scarecrow (End Device)
       └── RIP Tombstone (End Device)
```

## License

See parent project LICENSE file.
