# RIP Tombstone - Xiao ESP32-C6 Project

ESP-IDF project for the Seeed Studio Xiao ESP32-C6 microcontroller.

## Hardware

- **Board**: Seeed Studio Xiao ESP32-C6
- **Chip**: ESP32-C6 (RISC-V single-core, 160MHz)
- **Memory**: 512KB SRAM, 4MB Flash
- **Wireless**: WiFi 6, Bluetooth 5, Zigbee, Thread
- **USB**: Native USB (no UART bridge needed)

## Requirements

- ESP-IDF v5.0 or later
- Python 3.8+
- `just` command runner

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

4. **Build the project**:
   ```bash
   just build
   ```

5. **Flash to device**:
   ```bash
   just flash
   ```

6. **Monitor output**:
   ```bash
   just monitor
   ```

## Flashing and Development Workflow

### Standard Build and Flash Sequence
```bash
# 1. Clean build artifacts
just clean

# 2. Erase flash completely
just erase rip

# 3. Build the project
just build

# 4. Flash to device (NO button pressing required!)
just flash rip

# 5. Monitor serial output
just monitor rip
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
- `just flash rip` - Flash firmware to device (auto bootloader mode)
- `just monitor rip` - Monitor serial output
- `just dev` - Build, flash, and monitor in one command
- `just menuconfig` - Configure project settings
- `just clean` - Clean build artifacts
- `just erase rip` - Erase flash completely
- `just check-device` - Check if device is connected
- `just info` - Show device information

## Project Structure

```
rip_tombstone/
├── CMakeLists.txt          # Root CMake file
├── Justfile                # Build commands
├── main/
│   ├── CMakeLists.txt      # Main component CMake
│   └── main.c              # Main application code
└── README.md
```

## Development Workflow

```bash
# Source ESP-IDF environment
. $HOME/esp/esp-idf/export.sh

# Build, flash, and monitor
just dev
```

## Bootloader Mode

If flashing fails, put the device in bootloader mode:
1. Hold BOOT button
2. Press and release RESET button
3. Release BOOT button

## Device Detection

The project uses `find-xiao-esp32c6.sh` script to automatically detect the device at `/dev/ttyACM*`.

## License

See parent project LICENSE file.
