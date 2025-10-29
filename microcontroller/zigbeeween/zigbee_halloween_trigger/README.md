# Zigbee Halloween Trigger - Xiao ESP32-C6 Project

ESP-IDF project for controlling a Halloween decoration's "try me" button via Zigbee with RTC-based sleep scheduling.

## Hardware

- **Board**: Seeed Studio Xiao ESP32-C6
- **Chip**: ESP32-C6 (RISC-V single-core, 160MHz)
- **Memory**: 512KB SRAM, 4MB Flash
- **Wireless**: WiFi 6, Bluetooth 5, Zigbee, Thread
- **USB**: Native USB (no UART bridge needed)
- **RTC**: Adafruit DS3231 Precision RTC Breakout
- **Output**: Transistor/relay to trigger decoration button

## Features

- Zigbee end device with On/Off cluster
- Triggers Halloween decoration when receiving Zigbee "on" command
- DS3231 RTC for accurate timekeeping
- Automatic deep sleep from 12am to 6am to save power
- Visual feedback via built-in LED
- 5-second cooldown between triggers

## Pin Connections

### DS3231 RTC Breakout
- **VCC** → 3.3V
- **GND** → GND
- **SDA** → GPIO 6
- **SCL** → GPIO 7

### Trigger Output
- **GPIO 18** → Base of NPN transistor or relay input
  - Use transistor (e.g., 2N2222) to interface with decoration button
  - Connect emitter to GND
  - Connect collector to one side of button
  - Connect other side of button to decoration's button terminal

### Built-in Components
- **GPIO 15** → Built-in yellow LED (status indicator)

## Wiring Diagram

```
DS3231 RTC:
  VCC → 3.3V
  GND → GND
  SDA → GPIO 6
  SCL → GPIO 7

Trigger Circuit:
  GPIO 18 → 1kΩ resistor → 2N2222 Base
  2N2222 Emitter → GND
  2N2222 Collector → Decoration "Try Me" Button Terminal 1
  Button Terminal 2 → Decoration Circuit
```

## Requirements

- ESP-IDF v5.0 or later
- Python 3.8+
- `just` command runner
- Zigbee coordinator (Zigbee2MQTT, Home Assistant ZHA, etc.)

## Quick Start

1. **Install ESP-IDF**:
   ```bash
   # Follow official guide: https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/
   ```

2. **Set up ESP-IDF environment** (required before each session):
   ```bash
   . $HOME/esp/esp-idf/export.sh
   # OR if installed system-wide:
   . /opt/esp-idf/export.sh
   ```

3. **Set the target chip** (one-time setup):
   ```bash
   just set-target
   ```

4. **Configure Zigbee settings** (optional):
   ```bash
   just menuconfig
   # Navigate to Component config → Zigbee
   ```

5. **Build the project**:
   ```bash
   just build
   ```

6. **Flash to device**:
   ```bash
   just flash
   ```

7. **Monitor output**:
   ```bash
   just monitor
   ```

## Available Commands

Run `just` to see all available commands:

- `just build` - Build the project
- `just flash` - Flash firmware to device
- `just monitor` - Monitor serial output
- `just dev` - Build, flash, and monitor in one command
- `just menuconfig` - Configure project settings
- `just clean` - Clean build artifacts
- `just erase` - Erase flash completely
- `just check-device` - Check if device is connected
- `just info` - Show device information

## Project Structure

```
zigbee_halloween_trigger/
├── CMakeLists.txt          # Root CMake file
├── Justfile                # Build commands
├── main/
│   ├── CMakeLists.txt      # Main component CMake
│   ├── idf_component.yml   # Component dependencies
│   └── main.c              # Main application code
└── README.md
```

## Operation

### Startup
1. Device checks current time from DS3231 RTC
2. If time is between 12am-6am, enters deep sleep until 6am
3. If awake hours (6am-12am), starts Zigbee stack
4. Joins Zigbee network as an end device
5. Blinks LED 3 times to indicate ready state

### Trigger Behavior
1. Receives Zigbee "On" command from coordinator
2. Turns on built-in LED
3. Activates GPIO 18 (trigger pin) for 500ms
4. Turns off LED and trigger pin
5. Enters 5-second cooldown period

### Sleep Behavior
1. Checks RTC every minute
2. At 12am (midnight), calculates time until 6am
3. Enters deep sleep with timer wakeup
4. Wakes at 6am and resumes operation

## Zigbee Setup

### Pairing with Coordinator

1. Start the device
2. Put your Zigbee coordinator in pairing mode
3. Device will automatically attempt to join the network
4. Look for "On/Off Output" device in your coordinator

### Zigbee2MQTT Configuration

Add to `configuration.yaml`:
```yaml
devices:
  '0x00124b001234abcd':  # Your device IEEE address
    friendly_name: 'Halloween Trigger'
```

### Home Assistant

The device will appear as a switch entity. Create an automation:
```yaml
automation:
  - alias: "Trigger Halloween Decoration"
    trigger:
      - platform: state
        entity_id: binary_sensor.motion_sensor
        to: 'on'
    action:
      - service: switch.turn_on
        entity_id: switch.halloween_trigger
```

## DS3231 Setup

### Setting the Time

You can set the RTC time using an Arduino sketch or Python script before installing in the project.

**Arduino Example:**
```cpp
#include <RTClib.h>
RTC_DS3231 rtc;

void setup() {
  rtc.begin();
  rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
}
```

**Python Example (using smbus):**
```python
import smbus
from datetime import datetime

bus = smbus.SMBus(1)
now = datetime.now()

bus.write_byte_data(0x68, 0x00, ((now.second // 10) << 4) | (now.second % 10))
bus.write_byte_data(0x68, 0x01, ((now.minute // 10) << 4) | (now.minute % 10))
bus.write_byte_data(0x68, 0x02, ((now.hour // 10) << 4) | (now.hour % 10))
```

## Power Considerations

- Active mode (Zigbee on): ~80-100mA
- Deep sleep mode: ~10-20µA (RTC keeps time)
- 6-hour sleep period saves ~480-600mAh per night
- Can run on battery (LiPo) with solar charging

## Troubleshooting

### Device won't join Zigbee network
- Check that coordinator is in pairing mode
- Verify Zigbee is enabled in menuconfig
- Try resetting the device and coordinator
- Check coordinator logs for pairing attempts

### RTC time is wrong
- DS3231 has a backup battery (CR2032) for timekeeping
- Replace battery if time resets on power cycle
- Verify I2C connections (SDA, SCL)
- Check I2C address (should be 0x68)

### Trigger doesn't activate decoration
- Verify transistor wiring and orientation
- Check GPIO 18 voltage (should be 3.3V when active)
- Test with LED + resistor on GPIO 18 first
- Measure trigger duration (should be 500ms)

### Device sleeps at wrong time
- Verify RTC time is set correctly
- Check timezone settings in code
- Monitor serial output to see detected time

## Bootloader Mode

If flashing fails, put the device in bootloader mode:
1. Hold BOOT button
2. Press and release RESET button
3. Release BOOT button

## Device Detection

The project uses `find-xiao-esp32c6.sh` script to automatically detect the device at `/dev/ttyACM*`.

## Customization

### Change Sleep Hours
Edit `main/main.c`:
```c
#define SLEEP_START_HOUR 0  // Midnight
#define SLEEP_END_HOUR 6    // 6am
```

### Change Trigger Duration
Edit `main/main.c`:
```c
#define TRIGGER_DURATION_MS 500  // milliseconds
```

### Change Cooldown Period
Edit `main/main.c` in `trigger_button()`:
```c
vTaskDelay(pdMS_TO_TICKS(5000));  // 5 seconds
```

## License

See parent project LICENSE file.
