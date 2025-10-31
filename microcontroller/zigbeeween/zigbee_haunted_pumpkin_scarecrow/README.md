# Zigbee Haunted Pumpkin Scarecrow - Xiao ESP32-C6 Project

ESP-IDF project for controlling the haunted pumpkin scarecrow Halloween decoration via Zigbee using a relay module with time-synchronized sleep scheduling.

## Hardware

- **Board**: Seeed Studio Xiao ESP32-C6
- **Chip**: ESP32-C6 (RISC-V single-core, 160MHz)
- **Memory**: 512KB SRAM, 4MB Flash
- **Wireless**: WiFi 6, Bluetooth 5, Zigbee, Thread (using **internal antenna**)
- **USB**: Native USB for power and programming
- **Relay Module**: SainSmart 2-Channel 5V Relay Module
- **Power**: USB-powered (5V via USB-C)

## Features

- Zigbee end device with On/Off cluster
- Triggers relay when receiving Zigbee "on" command from coordinator
- **Time synchronization via Zigbee** - no external RTC required!
- Automatic deep sleep from 12am to 6am to save power
- Visual feedback via built-in LED
- 5-second cooldown between triggers
- Configurable active-low or active-high relay control

## Pin Connections

### SainSmart 2-Channel 5V Relay Module

The relay module has the following connections:

**Power:**
- **VCC** → 5V (from USB power or separate 5V supply)
- **GND** → GND (common ground with ESP32-C6)

**Control (choose one channel):**
- **IN1** → GPIO 18 (D10 on Xiao ESP32-C6 silkscreen)
- **IN2** → Not connected (unless you need a second channel)

**Relay Outputs:**
- Each relay has 3 terminals: **NC** (Normally Closed), **COM** (Common), **NO** (Normally Open)
- Use **COM** and **NO** for normally-open switching
- Connect decoration trigger wire between **COM** and **NO** on Relay 1

### Built-in Components
- **GPIO 15** → Built-in yellow LED (status indicator, lights up when relay triggers)

### Notes on Relay Module
- Most SainSmart modules are **active-LOW** (relay closes when GPIO is LOW)
- The module has built-in opto-isolators and works with 3.3V GPIO from ESP32-C6
- If your module doesn't trigger, set `RELAY_ACTIVE_LOW 0` in main.c line 28

## Wiring Diagram

```
ESP32-C6 (Xiao) Connections:
  USB-C → 5V Power (powers both ESP32-C6 and relay module)
  GND → Relay Module GND
  GPIO 18 (D9) → Relay Module IN1

Relay Module Connections:
  VCC → 5V (shared with ESP32-C6 USB power)
  GND → Common ground
  IN1 → GPIO 18 from ESP32-C6
  IN2 → Not connected

Halloween Decoration Connection:
  Decoration Wire 1 → Relay COM (Common)
  Decoration Wire 2 → Relay NO (Normally Open)

When trigger fires: Relay closes for 500ms, connecting COM to NO
```

## Power Supply

**USB-Powered Setup (Recommended):**
```
USB 5V Power → ESP32-C6 USB-C port
ESP32-C6 5V pin (or separate 5V wire) → Relay Module VCC
Common GND between all components
```

**Important:** The relay module draws more current than the ESP32-C6 can provide from its 3.3V regulator. Use the 5V USB power directly for the relay module VCC.

## System Architecture

This device is part of the Zigbee Halloween system:

```
Internet → TinyS3 (ESP32-S3) WiFi/HTTP Controller
             ↓ UART
          XIAO C6 Zigbee Coordinator ←→ (Zigbee) ←→ THIS DEVICE (End Device)
             ↓ UART                                      ↓
          Time Sync ─────────────────────────→ Time Sync via Zigbee
```

**Key Features:**
1. This device connects to the **Zigbee Border Gateway** (XIAO C6 coordinator)
2. Time is synchronized **wirelessly via Zigbee** (no RTC chip needed!)
3. The gateway's web page shows time sync status for all devices
4. Motion detection at the gateway triggers this device via Zigbee

## Requirements

- ESP-IDF v5.0 or later
- Python 3.8+
- `just` command runner
- **Zigbee Border Gateway** (see ../zigbee_border_gateway/) running and configured

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

## Flashing and Development Workflow

### Standard Build and Flash Sequence
```bash
# 1. Clean build artifacts
just clean

# 2. Erase flash completely
just erase scarecrow

# 3. Build the project
just build

# 4. Flash to device (NO button pressing required!)
just flash scarecrow

# 5. Monitor serial output
just monitor scarecrow
```

### Quick Rebuild (no sdkconfig changes)
If you're just modifying code and haven't changed `sdkconfig.defaults`:
- In monitor: Press `Control+T` then `Control+F` to rebuild and flash
- Much faster than full clean build

### When to Use Full Clean Build
You MUST do a full clean build when:
- Changing `sdkconfig.defaults` settings
- Running `menuconfig` and modifying options
- Build errors that seem unrelated to code changes
- After updating managed components

**Important**: The XIAO ESP32-C6 buttons are tiny, but the Justfile automatically handles bootloader mode - no button pressing needed!

## Available Commands

Run `just` to see all available commands:

- `just build` - Build the project
- `just flash scarecrow` - Flash firmware to device (auto bootloader mode)
- `just monitor scarecrow` - Monitor serial output
- `just dev` - Build, flash, and monitor in one command
- `just menuconfig` - Configure project settings
- `just clean` - Clean build artifacts
- `just erase scarecrow` - Erase flash completely
- `just check-device` - Check if device is connected
- `just info` - Show device information

## Project Structure

```
zigbee_haunted_pumpkin_scarecrow/
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
1. Device initializes and starts Zigbee stack
2. Joins Zigbee network as an end device
3. **Receives time synchronization from coordinator via Zigbee**
4. If time is synced and between 12am-6am, enters deep sleep until 6am
5. If awake hours (6am-12am), blinks LED 3 times to indicate ready state

### Time Synchronization
1. Coordinator broadcasts time updates every 5 minutes via custom Zigbee cluster
2. Device updates its internal clock automatically
3. Gateway web page shows sync status for all devices
4. **No external RTC required** - time is maintained by the coordinator

### Trigger Behavior
1. Receives Zigbee "On" command from coordinator
2. Turns on built-in LED for visual feedback
3. **Activates relay** (GPIO 18 → IN1) for 500ms
4. Relay closes, connecting COM to NO terminals
5. Turns off LED and relay
6. Enters 5-second cooldown period to prevent rapid retriggering

### Sleep Behavior
1. Checks system time every minute
2. At 12am (midnight), calculates time until 6am
3. Enters deep sleep with timer wakeup
4. Wakes at 6am and resumes operation
5. Requests time sync from coordinator after waking

## Zigbee Setup

### Pairing with Border Gateway Coordinator

1. **Start the Border Gateway** first (see ../zigbee_border_gateway/README.md)
2. Start this device (it will power up via USB)
3. Device will automatically attempt to join the Zigbee network
4. Look for connection confirmation in the serial monitor
5. Check the **gateway web page** to verify:
   - Device shows as "✓ Connected"
   - Time sync shows as "✓ Synced"

### Viewing Status

Access the border gateway web interface:
```
http://<gateway-ip>/
```

You'll see:
- **RIP Tombstone**: ✓ Connected (Time: ✓ Synced)
- **Haunted Pumpkin Scarecrow**: ✓ Connected (Time: ✓ Synced)
- PIR Motion Detection status
- Manual trigger buttons

### Testing the Relay

From the web interface:
1. Click "🎃 Trigger Pumpkin Scarecrow" button
2. Device LED should light up for 500ms
3. Relay should click (audible)
4. Connected decoration should activate

## Power Considerations

- Active mode (Zigbee on): ~80-100mA
- Deep sleep mode: ~10-20µA (time maintained by coordinator)
- 6-hour sleep period saves ~480-600mAh per night
- Relay module adds ~70-90mA when energized (500ms duration)
- USB-powered: Ensure power supply can provide 200mA minimum

## Troubleshooting

### Device won't join Zigbee network
- Verify the **Border Gateway** is running and accessible
- Check that Zigbee coordinator formed network (check gateway serial log)
- Try power-cycling this device
- Check distance - ensure within Zigbee range (~10-30 meters indoors)
- Monitor this device's serial output for pairing attempts

### Time not syncing
- Check gateway web page - does it show "✗ Not synced"?
- Verify gateway has internet and NTP time sync is working
- Check gateway serial logs for "Broadcasting time sync" messages
- Power-cycle this device to force re-sync
- Check Zigbee signal strength (devices may need to be closer)

### Relay doesn't trigger
- Verify relay module has 5V power
- Check wiring: GPIO 18 → Relay IN1
- Listen for relay "click" sound when triggering
- If no click: try changing `RELAY_ACTIVE_LOW` in main.c (line 28)
  - Set to `0` if module is active-HIGH
  - Set to `1` if module is active-LOW (default, most common)
- Test with LED: GPIO 18 should toggle HIGH/LOW during trigger
- Check relay module LED indicators

### Relay clicks but decoration doesn't activate
- Verify decoration wires connected to relay COM and NO terminals
- Test decoration independently to ensure it works
- Check if decoration needs more current than relay can handle (10A max)
- Try connecting decoration to opposite relay terminals (NC instead of NO)

### Device sleeps at wrong time
- Check time sync status on gateway web page
- Monitor serial output to see current time
- Timezone is set to Los Angeles (PST/PDT) - modify if needed
- Verify gateway has correct time from NTP

## Bootloader Mode

If flashing fails, put the device in bootloader mode:
1. Hold BOOT button
2. Press and release RESET button
3. Release BOOT button

## Device Detection

The project uses `find-xiao-esp32c6.sh` script to automatically detect the device at `/dev/ttyACM*`.

## Customization

### Change Sleep Hours
Edit `main/main.c` (lines 34-35):
```c
#define SLEEP_START_HOUR 0  // Midnight
#define SLEEP_END_HOUR 6    // 6am
```

### Change Relay Trigger Duration
Edit `main/main.c` (line 31):
```c
#define RELAY_TRIGGER_DURATION_MS 500  // milliseconds (time relay stays closed)
```

### Change Cooldown Period
Edit `main/main.c` in `trigger_relay()` function (line 167):
```c
vTaskDelay(pdMS_TO_TICKS(5000));  // 5 seconds between triggers
```

### Change Relay Control Logic (Active-Low vs Active-High)
Edit `main/main.c` (line 28):
```c
#define RELAY_ACTIVE_LOW 1  // 1 = active-LOW (most common), 0 = active-HIGH
```

### Add Second Relay Channel
To control both relay channels:
1. Define second pin in `main/main.c`:
```c
#define RELAY_TRIGGER_PIN_2 GPIO_NUM_19  // For second channel
```
2. Add setup code in `setup_relay_pin()`
3. Modify `trigger_relay()` to activate both pins

## License

See parent project LICENSE file.
