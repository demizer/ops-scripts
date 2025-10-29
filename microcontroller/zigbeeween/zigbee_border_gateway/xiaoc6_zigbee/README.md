# Zigbee Halloween Controller - TinyC6 ESP32-C6

ESP-IDF Zigbee coordinator project that controls Halloween decorations via web interface and PIR motion sensor.

## Overview

This project turns a TinyC6 ESP32-C6 into a **Zigbee coordinator** that:
- Acts as the central controller for Zigbee end devices
- Provides a web interface for manual control
- Automatically triggers devices when PIR motion is detected
- Displays status on an OLED screen
- Syncs time via NTP (Los Angeles timezone)

## Hardware

- **Board**: TinyC6 (also known as TinyPICO ESP32-C6)
- **Chip**: ESP32-C6 (RISC-V single-core, 160MHz)
- **Memory**: 512KB SRAM, 4MB Flash
- **Wireless**: WiFi 6, Bluetooth 5, Zigbee, Thread
- **USB**: Native USB (no UART bridge needed)
- **PIR Sensor**: Adafruit PIR motion sensor
- **OLED**: 128x32 SSD1306 I2C display
- **LED**: Built-in WS2812 NeoPixel

## Features

- **Zigbee Coordinator**: Network controller for end devices
- **Web Interface**: Browser-based control panel
- **PIR Motion Detection**: Auto-trigger on motion
- **OLED Display**: Real-time status updates
- **NTP Time Sync**: Accurate timekeeping (Los Angeles TZ)
- **WiFi Connectivity**: Web server and time sync
- **Dual Control**: Manual (web) and automatic (PIR)

## Pin Connections

### PIR Motion Sensor
- **VCC** → 3.3V or 5V (depending on sensor)
- **GND** → GND
- **OUT** → GPIO 9

### OLED Display (128x32 SSD1306)
- **VCC** → 3.3V
- **GND** → GND
- **SDA** → GPIO 6
- **SCL** → GPIO 7

### Built-in Components
- **GPIO 8** → Built-in WS2812 NeoPixel LED

## Wiring Diagram

```
TinyC6 ESP32-C6:
  GPIO 6 → OLED SDA
  GPIO 7 → OLED SCL
  GPIO 9 → PIR Sensor OUT
  GPIO 8 → Built-in NeoPixel (no external connection)

OLED Display (128x32):
  VCC → 3.3V
  GND → GND
  SDA → GPIO 6
  SCL → GPIO 7

PIR Sensor:
  VCC → 3.3V/5V (check sensor specs)
  GND → GND
  OUT → GPIO 9
```

## Requirements

- ESP-IDF v5.0 or later
- Python 3.8+
- `just` command runner
- WiFi network (2.4GHz)

## Quick Start

### 1. Install ESP-IDF

Follow the official guide: https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/

### 2. Set up ESP-IDF environment

Run this before each session:
```bash
. $HOME/esp/esp-idf/export.sh
# OR if installed system-wide:
. /opt/esp-idf/export.sh
```

### 3. Set the target chip

One-time setup:
```bash
just set-target
```

### 4. Configure WiFi credentials

**CRITICAL**: You must configure WiFi settings:
```bash
just menuconfig
```

Navigate to:
- **Zigbee Halloween Controller Configuration**
- Set **WiFi SSID** to your WiFi network name
- Set **WiFi Password** to your WiFi password
- Save and exit (press 'S', then 'Q')

### 5. Build and flash

```bash
just build       # Compile firmware
just flash       # Upload to device
just monitor     # View serial output

# Or do all at once:
just dev
```

### 6. Access web interface

After flashing, check the serial monitor for output like:
```
I (12345) zigbee_controller: Got IP: 192.168.1.100
```

Open your browser to: `http://192.168.1.100/`

## Available Commands

Run `just` or `just --list` to see all commands:

- `just set-target` - Configure for ESP32-C6 (one-time)
- `just menuconfig` - Configure WiFi and settings
- `just build` - Build the firmware
- `just flash` - Flash firmware to device
- `just monitor` - Monitor serial output
- `just dev` - Build, flash, and monitor in one command
- `just clean` - Clean build artifacts
- `just erase` - Erase flash completely
- `just check-device` - Check if device is connected
- `just info` - Show project information
- `just help` - Show quick start guide

## Project Structure

```
zigbee_controller/
├── CMakeLists.txt          # Root CMake configuration
├── Justfile                # Build commands
├── sdkconfig.defaults      # Default configuration
├── partitions.csv          # Flash partition table
├── main/
│   ├── CMakeLists.txt      # Main component CMake
│   ├── idf_component.yml   # Component dependencies
│   └── main.c              # Main application code
├── find-tinyc6.sh          # Device detection script
└── README.md               # This file
```

## Operation

### Startup Sequence

1. **Hardware initialization**: I2C, OLED, PIR sensor
2. **WiFi connection**: Connects to configured network
3. **NTP time sync**: Syncs with Los Angeles timezone
4. **Web server start**: HTTP server on port 80
5. **Zigbee coordinator**: Forms Zigbee network
6. **PIR monitoring**: Starts motion detection loop
7. **Status display**: Shows "Ready!" on OLED

### Web Interface

Access the web interface at `http://<device-ip>/` to see:

- Current time (Los Angeles timezone)
- PIR motion status
- Connected device status
- Manual control buttons:
  - **🪦 Trigger RIP Tombstone** - Activate tombstone decoration
  - **🎃 Trigger Halloween** - Activate try-me decoration
  - **👻 Trigger BOTH** - Activate both devices

### Automatic Mode

When PIR sensor detects motion:
1. OLED displays "MOTION!"
2. Log message appears in serial monitor
3. **Both devices are triggered automatically**
4. Brief delay between triggers (200ms)

### Zigbee Network

The coordinator will:
- Form a new Zigbee network on first boot
- Allow end devices to join
- Send On/Off commands to paired devices
- Maintain device bindings

**End devices to pair:**
1. **zigbee_rip_tombstone** (Xiao ESP32-C6)
2. **zigbee_halloween_trigger** (Xiao ESP32-C6)

## Configuration

### WiFi Settings

Edit via menuconfig:
```bash
just menuconfig
# Navigate to: Zigbee Halloween Controller Configuration
```

### Zigbee Channel

Edit `main/main.c`:
```c
#define ESP_ZB_PRIMARY_CHANNEL_MASK ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK
```

### PIR Sensor Pin

Edit `main/main.c`:
```c
#define PIR_PIN GPIO_NUM_9
```

### Time Zone

Edit `main/main.c`:
```c
setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);  // Los Angeles
```

Common timezones:
- Los Angeles: `PST8PDT,M3.2.0,M11.1.0`
- New York: `EST5EDT,M3.2.0,M11.1.0`
- Chicago: `CST6CDT,M3.2.0,M11.1.0`
- Denver: `MST7MDT,M3.2.0,M11.1.0`
- UTC: `UTC0`

## Troubleshooting

### WiFi won't connect
- Check SSID and password in menuconfig
- Ensure 2.4GHz WiFi (ESP32-C6 doesn't support 5GHz)
- Check serial monitor for connection errors
- Verify WiFi router is in range

### Can't access web interface
- Check serial monitor for IP address
- Verify device and computer on same network
- Try pinging the device: `ping <device-ip>`
- Check router firewall settings

### Zigbee devices won't pair
- Put end devices in pairing mode
- Check coordinator logs in serial monitor
- Verify Zigbee channel compatibility
- Try resetting both devices

### OLED display not working
- Check I2C connections (GPIO 6/7)
- Verify OLED address is 0x3C
- Check power (3.3V) to display
- Try different I2C speed in code

### PIR sensor not detecting
- Allow 30-60 seconds warm-up time
- Check PIR power (some need 5V)
- Verify GPIO 9 connection
- Adjust sensor sensitivity potentiometers
- Test with multimeter (should read HIGH when motion detected)

### Time not syncing
- Verify WiFi connection is active
- Check NTP server accessibility
- Wait 2-5 seconds after boot
- Monitor serial output for sync messages

## Bootloader Mode

If flashing fails, manually enter bootloader mode:
1. **Hold BOOT button**
2. **Press and release RESET button**
3. **Release BOOT button**
4. Run `just flash`

## Device Detection

The project uses `find-tinyc6.sh` to automatically detect the TinyC6 at `/dev/ttyACM*`.

The script looks for USB device ID `303a:1001` (Espressif USB JTAG).

## Web API Endpoints

Manual control via HTTP POST:

```bash
# Trigger RIP Tombstone
curl -X POST http://<device-ip>/trigger/rip

# Trigger Halloween decoration
curl -X POST http://<device-ip>/trigger/halloween

# Trigger both devices
curl -X POST http://<device-ip>/trigger/both
```

## Advanced Configuration

### Adjust Web Server Port

Edit `main/main.c`:
```c
httpd_config_t config = HTTPD_DEFAULT_CONFIG();
config.server_port = 8080;  // Change from default 80
```

### Change Motion Trigger Delay

Edit `main/main.c` in `pir_monitor_task()`:
```c
vTaskDelay(pdMS_TO_TICKS(200));  // Delay between device triggers
```

### Customize OLED Messages

Edit `oled_print()` calls in `main/main.c`:
```c
oled_print("Your custom message");
```

## Power Consumption

- **Active (WiFi + Zigbee)**: ~150-200mA
- **WiFi only**: ~100-120mA
- **Zigbee only**: ~80-100mA
- **Deep sleep**: ~10-20µA (if implemented)

Not ideal for battery operation due to constant WiFi/Zigbee/OLED usage.

## System Architecture

```
┌─────────────────────────────────────────┐
│      TinyC6 Zigbee Coordinator          │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │   WiFi   │  │  Zigbee  │            │
│  │  Server  │  │   Radio  │            │
│  └────┬─────┘  └────┬─────┘            │
│       │             │                   │
│  ┌────▼─────────────▼─────┐            │
│  │    Main Controller      │            │
│  │  - PIR monitoring       │            │
│  │  - Device coordination  │            │
│  │  - Time sync            │            │
│  └────┬────────────────────┘            │
│       │                                 │
│  ┌────▼────┐                            │
│  │  OLED   │                            │
│  │ Display │                            │
│  └─────────┘                            │
└─────────────────────────────────────────┘
         │                    │
         │                    │
    ┌────▼────┐         ┌────▼─────┐
    │   RIP   │         │Halloween │
    │Tombstone│         │ Trigger  │
    │(Zigbee) │         │ (Zigbee) │
    └─────────┘         └──────────┘
```

## Home Automation Integration

This coordinator can work alongside:
- **Zigbee2MQTT**: Expose devices to MQTT
- **Home Assistant ZHA**: Direct integration
- **OpenHAB**: Zigbee binding support
- **Node-RED**: HTTP API integration

## Future Enhancements

Potential improvements:
- [ ] Deep sleep mode for battery operation
- [ ] OTA (Over-The-Air) firmware updates
- [ ] MQTT publishing for home automation
- [ ] Scheduled triggers (based on time)
- [ ] Web-based configuration (no menuconfig needed)
- [ ] Device pairing via web interface
- [ ] Battery monitoring (if running on LiPo)

## License

See parent project LICENSE file.

## Credits

- ESP-IDF by Espressif Systems
- TinyC6 hardware by TinyPICO/Unexpected Maker
- Halloween spirit by the community 🎃

## Support

For issues specific to:
- **ESP-IDF**: Check Espressif documentation
- **TinyC6 hardware**: Contact manufacturer
- **This project**: Open an issue in the repository

---

**Happy Halloween! 🎃👻🪦**
