# TinyC6 ESP32-S3 PIR Motion Sensor

A CircuitPython project for the TinyC6 ESP32-S3 microcontroller that detects motion using a PIR sensor and displays status on an OLED screen.

## Hardware Setup

- **TinyC6 ESP32-S3** microcontroller
- **128x32 SSD1306 OLED** display connected via I2C (pins IO6/IO7)
- **Adafruit PIR motion sensor** connected to pin IO18
- **Built-in NeoPixel** LED for motion indication
- **3.7V 2500mAh LiPo** battery (optional, for battery life testing)

### Wiring

| Component | TinyC6 Pin | Notes |
|-----------|------------|-------|
| OLED SDA | IO6 | I2C Data |
| OLED SCL | IO7 | I2C Clock |
| PIR Sensor | IO18 | Digital input with pull-down |
| NeoPixel | Built-in | NEOPIXEL pin |
| Battery | VBAT | Built-in battery monitoring |
| USB Detection | GPIO10 | Built-in 5V detection |

## Features

- **Motion Detection**: PIR sensor triggers green NeoPixel LED
- **OLED Display**: Shows motion status, battery level, and USB connection
- **Battery Monitoring**: Tracks 3.7V LiPo battery voltage and percentage
- **USB Detection**: Automatically detects when USB power is connected
- **Data Logging**: Creates start/end files for battery life testing
- **Low Battery Protection**: Graceful shutdown at 5% battery

## Flashing to Device

### Prerequisites

Install the required tools:
```bash
# Install CircuitPython CLI tools
pip install circup adafruit-circuitpython-bundle

# Or use the Justfile (recommended)
just install-deps
```

### Using the Justfile

This project includes a `Justfile` for easy device management:

```bash
# Install CircuitPython on the device
just flash-circuitpython

# Copy code to the device
just deploy

# Monitor serial output
just monitor

# Complete setup (flash + deploy + monitor)
just setup

# List available commands
just --list
```

### Manual Flashing

1. **Install CircuitPython firmware** on your TinyC6:
   - Download CircuitPython UF2 file for ESP32-C6 from [circuitpython.org](https://circuitpython.org/board/espressif_esp32c6_devkitc_1/)
   - Put device in bootloader mode (hold BOOT button while pressing RESET)
   - Copy UF2 file to the device when it appears as USB drive

2. **Install required libraries**:
   ```bash
   # Device should appear as CIRCUITPY drive
   circup install adafruit_displayio_ssd1306 adafruit_display_text rainbowio
   ```

3. **Copy the code**:
   ```bash
   # Copy code.py to the CIRCUITPY drive
   cp code.py /media/CIRCUITPY/
   ```

4. **Monitor output**:
   ```bash
   # Connect to serial console (Linux/macOS)
   screen /dev/ttyACM0 115200

   # Or use Python
   python -m serial.tools.miniterm /dev/ttyACM0 115200
   ```

## Operation

When the program starts:
1. OLED displays "Starting..." and initializes all sensors
2. Creates a startup log file (`pir_motion_test_start.txt`)
3. Continuously monitors PIR sensor every 100ms
4. Green NeoPixel lights up when motion is detected
5. OLED shows current motion status and battery information
6. Logs battery life data for testing purposes

### Display Layout

```
Motion Status    Batt%
Motion Info      USB/Voltage
```

Example:
```
MOTION!          85%
Green LED ON     4.1V
```

## Battery Life Testing

The program automatically tracks battery usage:
- **Start file**: `pir_motion_test_start.txt` - Created on startup
- **End file**: `pir_motion_test_end.txt` - Created on low battery shutdown
- **Low battery threshold**: 5% (configurable in code)
- **Critical shutdown**: 3% battery

## Troubleshooting

### Device Not Detected
- Check USB cable (data cable, not charge-only)
- Try different USB port
- Press RESET button on device

### Libraries Missing
```bash
# Reinstall CircuitPython libraries
circup install --force adafruit_displayio_ssd1306 adafruit_display_text rainbowio
```

### OLED Not Working
- Check I2C connections (IO6=SDA, IO7=SCL)
- Verify OLED address is 0x3C
- Try different I2C pins if needed

### PIR Sensor Not Working
- Check connection to IO18
- Verify sensor has power (3.3V/5V depending on sensor)
- PIR sensors may need 30-60 seconds to calibrate after power-on

## File Structure

```
zigbeeween/
├── code.py          # Main CircuitPython program
├── README.md        # This file
└── Justfile        # Build automation
```

## Development

To modify the code:
1. Edit `code.py` with your changes
2. Use `just deploy` to copy to device
3. Use `just monitor` to see output
4. Device will automatically restart when code.py changes