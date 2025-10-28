import time
import board
import neopixel
import busio
import displayio
from adafruit_displayio_ssd1306 import SSD1306
from adafruit_display_text import label
import terminalio
from i2cdisplaybus import I2CDisplayBus
from analogio import AnalogIn
from digitalio import DigitalInOut, Direction, Pull
import microcontroller
import sys

# Clear any previous displays
displayio.release_displays()

# Set up I2C and OLED (using pin 18 as specified)
i2c = busio.I2C(board.IO7, board.IO6)
display_bus = I2CDisplayBus(i2c, device_address=0x3C)
display = SSD1306(display_bus, width=128, height=32)

# Set up NeoPixel
pixel = neopixel.NeoPixel(board.NEOPIXEL, 1)
pixel.brightness = 0.3

# Set up PIR motion sensor on pin 9
# NOTE: Sensor is 5V powered Arduino sensor, may need level shifting
# Some PIR sensors are active-low (output LOW on motion, HIGH when idle)
pir_pin = DigitalInOut(board.IO9)
pir_pin.direction = Direction.INPUT
pir_pin.pull = Pull.DOWN  # Pull down to prevent floating when no motion

# Helper function to read PIR with inverted logic option
def read_pir_sensor(inverted=False):
    """Read PIR sensor with optional logic inversion"""
    value = pir_pin.value
    return not value if inverted else value

# Set up battery monitoring
vbat_voltage = AnalogIn(board.VBAT)

# Set up USB detection using GPIO10 (DETECT 5V PRESENT)
gpio10_pin = microcontroller.pin.GPIO10
usb_pin = DigitalInOut(gpio10_pin)
usb_pin.direction = Direction.INPUT
usb_pin.pull = Pull.DOWN

# BATTERY LIFE TEST SETUP
START_TIME = time.monotonic()  # Record start time
LOW_BATTERY_THRESHOLD = 5  # Shutdown at 5%

def write_start_file():
    """Write startup log file"""
    try:
        with open("/pir_motion_test_start.txt", "w") as f:
            f.write("TinyC6 PIR Motion Sensor Battery Life Test\n")
            f.write("=" * 45 + "\n")
            f.write(f"Test started: {time.localtime()}\n")
            f.write("Program: PIR Motion Detection with OLED display\n")
            f.write("Battery: 3.7V 2500mAh LiPo\n")
            f.write("NeoPixel brightness: 30%\n")
            f.write("OLED: 128x32 SSD1306\n")
            f.write("PIR Sensor: Pin 9\n")
            f.write(f"Low battery shutdown: {LOW_BATTERY_THRESHOLD}%\n")
            f.write(f"Start voltage: {get_battery_voltage():.2f}V\n")
            f.write("Test running...\n")
        print("✓ Start file written: /pir_motion_test_start.txt")
    except Exception as e:
        print(f"✗ Failed to write start file: {e}")

# def write_end_file(runtime_seconds, final_voltage, final_percentage):
#     """Write shutdown log file with runtime calculation"""
#     try:
#         # Calculate runtime in human-readable format
#         hours = int(runtime_seconds // 3600)
#         minutes = int((runtime_seconds % 3600) // 60)
#         seconds = int(runtime_seconds % 60)
#
#         with open("/pir_motion_test_end.txt", "w") as f:
#             f.write("TinyC6 PIR Motion Sensor Battery Life Test - COMPLETED\n")
#             f.write("=" * 55 + "\n")
#             f.write(f"Test ended: {time.localtime()}\n")
#             f.write(f"Shutdown reason: Battery reached {final_percentage}% (< {LOW_BATTERY_THRESHOLD}%)\n")
#             f.write(f"Final battery voltage: {final_voltage:.2f}V\n")
#             f.write(f"Final battery percentage: {final_percentage}%\n")
#             f.write("\n--- RUNTIME RESULTS ---\n")
#             f.write(f"Total runtime: {hours:02d}h {minutes:02d}m {seconds:02d}s\n")
#             f.write(f"Runtime in seconds: {runtime_seconds:.1f}s\n")
#             f.write(f"Runtime in minutes: {runtime_seconds/60:.1f} min\n")
#             f.write(f"Runtime in hours: {runtime_seconds/3600:.2f} hours\n")
#             f.write("\n--- BATTERY PERFORMANCE ---\n")
#             f.write(f"3.7V 2500mAh LiPo capacity used: {100 - final_percentage}%\n")
#             f.write(f"Estimated remaining capacity: {final_percentage}%\n")
#             f.write("\n--- POWER CONSUMPTION ---\n")
#             f.write("Components active during test:\n")
#             f.write("- NeoPixel LED (30% brightness, green on motion)\n")
#             f.write("- 128x32 OLED display (constantly updating)\n")
#             f.write("- ESP32-C6 microcontroller\n")
#             f.write("- PIR Motion Sensor (Pin 18)\n")
#             f.write("- I2C communication\n")
#             f.write("- Battery voltage monitoring\n")
#             f.write("- USB detection\n")
#             f.write("\nTest completed successfully!\n")
#         print("✓ End file written: /pir_motion_test_end.txt")
#         print(f"✓ Total runtime: {hours:02d}h {minutes:02d}m {seconds:02d}s")
#     except Exception as e:
#         print(f"✗ Failed to write end file: {e}")

def get_battery_voltage():
    """Read battery voltage for 3.7V 2500mAh LiPo"""
    raw_reading = vbat_voltage.value
    voltage = (raw_reading * 3.3) / 65536
    scaled_voltage = voltage * 4.0
    return scaled_voltage

def is_usb_connected():
    """USB detection using GPIO10 digital pin"""
    return usb_pin.value

def voltage_to_percentage(voltage, on_usb=False):
    """Convert 3.7V 2500mAh LiPo voltage to percentage"""
    # Calculate actual battery percentage from voltage regardless of USB status
    # 3.7V LiPo discharge curve
    if voltage >= 4.15:
        return 100
    elif voltage >= 4.0:
        return 90 + (voltage - 4.0) * 66
    elif voltage >= 3.85:
        return 70 + (voltage - 3.85) * 133
    elif voltage >= 3.7:
        return 40 + (voltage - 3.7) * 200
    elif voltage >= 3.5:
        return 15 + (voltage - 3.5) * 125
    elif voltage >= 3.3:
        return 5 + (voltage - 3.3) * 50
    else:
        return max(0, (voltage - 3.0) * 16.7)

def update_battery_display():
    """Update battery and USB status display"""
    battery_voltage = get_battery_voltage()
    usb_connected = is_usb_connected()
    battery_percent = voltage_to_percentage(battery_voltage, usb_connected)

    # Update battery percentage (top-right) with charging indicator
    if usb_connected:
        battery_percent_label.text = f"{int(battery_percent)}%+"
    else:
        battery_percent_label.text = f"{int(battery_percent)}%"

    # Update USB status (bottom-right)
    if usb_connected:
        usb_status_label.text = f"CHG {battery_voltage:.1f}V"
    else:
        usb_status_label.text = f"{battery_voltage:.1f}V"

    return battery_voltage, usb_connected, battery_percent

# def shutdown_sequence(runtime_seconds, final_voltage, final_percentage):
#     """Graceful shutdown sequence"""
#     print(f"🔋 LOW BATTERY SHUTDOWN - {final_percentage}%")
#     print(f"⏱️  Runtime: {runtime_seconds/3600:.2f} hours")
#
#     # Display shutdown message
#     motion_status_label.text = "LOW BATTERY"
#     motion_info_label.text = "SHUTTING DOWN"
#     battery_percent_label.text = f"{int(final_percentage)}%"
#     usb_status_label.text = "END"
#
#     # Turn off NeoPixel
#     pixel.fill((0, 0, 0))
#
#     # Write end file and exit
#     write_end_file(runtime_seconds, final_voltage, final_percentage)
#
#     print("🏁 PIR Motion test completed!")
#     print("📁 Check pir_motion_test_end.txt for results")
#
#     # Keep display on for 5 seconds before exit
#     time.sleep(5)
#     sys.exit()

# Create display group
splash = displayio.Group()
display.root_group = splash

motion_status_label = label.Label(terminalio.FONT, text="Starting...", color=0xFFFFFF, anchor_point=(0.0, 0.0), anchored_position=(2, 2))
# motion_info_label = label.Label(terminalio.FONT, text="PIR Motion", color=0xFFFFFF, anchor_point=(0.0, 1.0), anchored_position=(2, 30))
battery_percent_label = label.Label(terminalio.FONT, text="100%", color=0xFFFFFF, anchor_point=(1.0, 0.0), anchored_position=(126, 2))
usb_status_label = label.Label(terminalio.FONT, text="USB", color=0xFFFFFF, anchor_point=(1.0, 1.0), anchored_position=(126, 30))

splash.append(motion_status_label)
# splash.append(motion_info_label)
splash.append(battery_percent_label)
splash.append(usb_status_label)

# Write startup file
print("🔋 Starting TinyC6 PIR Motion Sensor Test")
write_start_file()

# PIR sensor warm-up and diagnostics
print("⏳ PIR sensor warming up and monitoring changes...")
print("⚠️  NOTE: If sensor stays HIGH constantly, adjust the time delay pot to minimum")
motion_status_label.text = "Warming up..."
print("🔍 Watching for pin changes (stay still for 120s)...")

last_value = read_pir_sensor()
true_count = 0
false_count = 0

for i in range(120, 0, -1):
    battery_voltage, usb_connected, battery_percent = update_battery_display()
    usb_status_label.text = f"Wait {i}s"

    # Read raw pin value for debugging
    raw_value = pir_pin.value
    current_value = read_pir_sensor()

    if current_value:
        true_count += 1
    else:
        false_count += 1

    # Show raw pin value every 5 seconds
    if i % 5 == 0:
        print(f"  [T-{i}s] Raw pin: {raw_value}, Processed: {current_value}")

    # Show when value changes
    if current_value != last_value:
        print(f"  🔄 PIR changed: {last_value} → {current_value} (raw: {raw_value})")
        last_value = current_value

    time.sleep(1)

print(f"✓ PIR sensor ready!")
print(f"🔍 True count: {true_count}, False count: {false_count}")
print(f"🔍 Final baseline: {read_pir_sensor()}")
print("📝 Now wave your hand in front of sensor...")
motion_status_label.text = f"T:{true_count}F:{false_count}"
usb_status_label.text = "USB" if is_usb_connected() else f"{get_battery_voltage():.1f}V"
time.sleep(2)

# Main program loop
last_battery_check = 0
last_pir_log = 0
last_pin_value = read_pir_sensor()
motion_detected = False

print(f"🔍 Starting with pin value: {last_pin_value}")

while True:
    current_time = time.monotonic()

    # Always check PIR sensor and update LED immediately (responsive)
    current_motion = read_pir_sensor()

    # Log any pin changes for debugging
    if current_motion != last_pin_value:
        print(f"🔄 PIN CHANGE: {last_pin_value} → {current_motion}")
        last_pin_value = current_motion

    # Update NeoPixel immediately based on motion detection
    if current_motion:
        pixel.fill((0, 255, 0))  # Green when motion detected
        if not motion_detected:  # Motion just started
            motion_status_label.text = "MOTION!"
            # motion_info_label.text = "Green LED ON"
            print("🟢 Motion detected!")
        motion_detected = True
    else:
        pixel.fill((0, 0, 0))    # Off when no motion
        if motion_detected:      # Motion just stopped
            motion_status_label.text = "No Motion"
            # motion_info_label.text = "LED OFF"
            print("⚫ No motion")
        motion_detected = False

    # Update battery status every 1 second
    if current_time - last_battery_check >= 1.0:
        battery_voltage, usb_connected, battery_percent = update_battery_display()

        # Calculate runtime
        runtime_seconds = current_time - START_TIME

        # LOW BATTERY CHECK
        if battery_percent < LOW_BATTERY_THRESHOLD and not usb_connected:
            print(f"⚠️  Low battery: {battery_percent:.1f}% - Runtime: {runtime_seconds/3600:.2f}h")
            # write_end_file(runtime_seconds, battery_voltage, battery_percent)

            # # If battery gets critically low, shutdown
            # if battery_percent < 3:
            #     shutdown_sequence(runtime_seconds, battery_voltage, battery_percent)

        last_battery_check = current_time

    time.sleep(0.1)  # Short sleep to keep loop responsive

