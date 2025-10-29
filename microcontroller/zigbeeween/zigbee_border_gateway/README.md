# Zigbee Border Gateway - Hardware Connections

## Overview

This system uses two microcontrollers:
- **TinyS3 (ESP32-S3)**: WiFi/HTTP controller with PIR sensor and OLED display
- **XIAO C6 (ESP32-C6)**: Zigbee coordinator

The devices communicate via UART.

## TinyS3 ESP32-S3 Pin Connections

### PIR Motion Sensor
- **PIR Data**: GPIO1
- **PIR VCC**: 3.3V
- **PIR GND**: GND

### OLED Display (SSD1306 128x32, I2C)
- **SDA**: GPIO8
- **SCL**: GPIO9
- **VCC**: 3.3V
- **GND**: GND

### UART to XIAO C6
- **TX**: GPIO43 (connects to XIAO C6 RX)
- **RX**: GPIO44 (connects to XIAO C6 TX)

## XIAO C6 ESP32-C6 Pin Connections

### UART to TinyS3
- **TX**: GPIO16 / D6 (connects to TinyS3 RX)
- **RX**: GPIO17 / D7 (connects to TinyS3 TX)

## Inter-Device Wiring

Connect the two devices via UART:

```
TinyS3 GPIO43 (TX) ----> XIAO C6 GPIO17 (RX/D7)
TinyS3 GPIO44 (RX) <---- XIAO C6 GPIO16 (TX/D6)
TinyS3 GND ------------- XIAO C6 GND (common ground required)
```

## Power

- Both devices can be powered independently via USB during development
- For production, ensure common ground between devices
- TinyS3: 5V via USB or 3.3V regulated
- XIAO C6: 5V via USB or 3.3V regulated

## Notes

- I2C pull-up resistors may be required for OLED (typically 4.7k ohm to 3.3V)
- PIR sensor output is typically 3.3V compatible
- UART communication is at 115200 baud, 8N1
- Ensure common ground between TinyS3 and XIAO C6 for reliable UART communication
