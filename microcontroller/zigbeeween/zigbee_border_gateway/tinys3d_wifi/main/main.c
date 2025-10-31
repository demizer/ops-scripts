#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_sntp.h"
#include "esp_http_server.h"
#include "nvs_flash.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "driver/uart.h"

static const char *TAG = "tinys3_controller";

// WiFi credentials (configure these!)
#define WIFI_SSID      CONFIG_ESP_WIFI_SSID
#define WIFI_PASS      CONFIG_ESP_WIFI_PASSWORD

// Pin definitions for TinyS3
#define PIR_PIN GPIO_NUM_1       // PIR motion sensor
#define I2C_SDA_PIN GPIO_NUM_8   // OLED SDA
#define I2C_SCL_PIN GPIO_NUM_9   // OLED SCL
#define OLED_ADDR 0x3C

// External antenna control for TinyS3D
#define ANTENNA_SELECT_PIN GPIO_NUM_38  // HIGH = external antenna, LOW = internal antenna

// UART pins for communication with XIAO C6 Zigbee coordinator
#define UART_TX_PIN GPIO_NUM_43  // TX to XIAO C6
#define UART_RX_PIN GPIO_NUM_44  // RX from XIAO C6
#define UART_NUM UART_NUM_1
#define UART_BUF_SIZE (1024)

// I2C configuration
#define I2C_MASTER_NUM I2C_NUM_0
#define I2C_MASTER_FREQ_HZ 100000

// Event group bits
#define WIFI_CONNECTED_BIT BIT0

// Global state
static EventGroupHandle_t s_wifi_event_group;
static int s_retry_num = 0;
static httpd_handle_t server = NULL;
static bool pir_motion_detected = false;
static bool time_synced = false;

// WiFi status for display
static char wifi_ssid[32] = "";
static char wifi_ip[16] = "0.0.0.0";
static int wifi_rssi = 0;

// Zigbee device status (received from XIAO C6 via UART)
typedef struct {
    char name[32];
    bool is_connected;
    bool time_synced;
    bool in_cooldown;
} zigbee_device_t;

static zigbee_device_t rip_tombstone = {"RIP Tombstone", false, false, false};
static zigbee_device_t halloween_trigger = {"Haunted Pumpkin Scarecrow", false, false, false};

// UART command protocol
#define CMD_TRIGGER_RIP 0x01
#define CMD_TRIGGER_HALLOWEEN 0x02
#define CMD_TRIGGER_BOTH 0x03
#define CMD_STATUS_REQUEST 0x10
#define CMD_STATUS_RESPONSE 0x11
#define CMD_TIME_SYNC 0x20
#define CMD_DEVICE_JOINED 0x30
#define CMD_DEVICE_LEFT 0x31

// Event logging
#define MAX_EVENTS 50
typedef enum {
    EVENT_MOTION_DETECTED,
    EVENT_MOTION_STOPPED,
    EVENT_TRIGGER_RIP,
    EVENT_TRIGGER_HALLOWEEN,
    EVENT_TRIGGER_BOTH,
    EVENT_DEVICE_JOINED,
    EVENT_DEVICE_LEFT
} event_type_t;

typedef struct {
    time_t timestamp;
    event_type_t type;
    char device_name[32];  // For join/leave events
} event_log_t;

static event_log_t event_log[MAX_EVENTS];
static int event_log_head = 0;
static int event_log_count = 0;

// ============================================================================
// Event Logging
// ============================================================================

void log_event(event_type_t type, const char *device_name)
{
    event_log[event_log_head].timestamp = time(NULL);
    event_log[event_log_head].type = type;

    if (device_name) {
        strncpy(event_log[event_log_head].device_name, device_name, sizeof(event_log[event_log_head].device_name) - 1);
        event_log[event_log_head].device_name[sizeof(event_log[event_log_head].device_name) - 1] = '\0';
    } else {
        event_log[event_log_head].device_name[0] = '\0';
    }

    event_log_head = (event_log_head + 1) % MAX_EVENTS;
    if (event_log_count < MAX_EVENTS) {
        event_log_count++;
    }

    // Log to console
    const char *event_name;
    switch (type) {
        case EVENT_MOTION_DETECTED: event_name = "Motion Detected"; break;
        case EVENT_MOTION_STOPPED: event_name = "Motion Stopped"; break;
        case EVENT_TRIGGER_RIP: event_name = "Trigger RIP"; break;
        case EVENT_TRIGGER_HALLOWEEN: event_name = "Trigger Pumpkin Scarecrow"; break;
        case EVENT_TRIGGER_BOTH: event_name = "Trigger Both"; break;
        case EVENT_DEVICE_JOINED: event_name = "Device Joined"; break;
        case EVENT_DEVICE_LEFT: event_name = "Device Left"; break;
        default: event_name = "Unknown"; break;
    }

    if (device_name) {
        ESP_LOGI(TAG, "Event logged: %s - %s", event_name, device_name);
    } else {
        ESP_LOGI(TAG, "Event logged: %s", event_name);
    }
}

// ============================================================================
// I2C and OLED Functions
// ============================================================================

void setup_i2c(void)
{
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = I2C_SDA_PIN,
        .scl_io_num = I2C_SCL_PIN,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = I2C_MASTER_FREQ_HZ,
    };

    ESP_ERROR_CHECK(i2c_param_config(I2C_MASTER_NUM, &conf));
    ESP_ERROR_CHECK(i2c_driver_install(I2C_MASTER_NUM, conf.mode, 0, 0, 0));

    ESP_LOGI(TAG, "I2C initialized for OLED display");
}

void oled_write_cmd(uint8_t cmd)
{
    i2c_cmd_handle_t i2c_cmd = i2c_cmd_link_create();
    i2c_master_start(i2c_cmd);
    i2c_master_write_byte(i2c_cmd, (OLED_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(i2c_cmd, 0x00, true); // Command mode
    i2c_master_write_byte(i2c_cmd, cmd, true);
    i2c_master_stop(i2c_cmd);
    i2c_master_cmd_begin(I2C_MASTER_NUM, i2c_cmd, pdMS_TO_TICKS(1000));
    i2c_cmd_link_delete(i2c_cmd);
}

void oled_init(void)
{
    vTaskDelay(pdMS_TO_TICKS(100));

    // Initialization sequence for 128x32 SSD1306
    oled_write_cmd(0xAE); // Display off
    oled_write_cmd(0xD5); // Set display clock
    oled_write_cmd(0x80);
    oled_write_cmd(0xA8); // Set multiplex ratio
    oled_write_cmd(0x1F); // 32 rows
    oled_write_cmd(0xD3); // Set display offset
    oled_write_cmd(0x00);
    oled_write_cmd(0x40); // Set start line
    oled_write_cmd(0x8D); // Charge pump
    oled_write_cmd(0x14);
    oled_write_cmd(0x20); // Memory mode
    oled_write_cmd(0x00); // Horizontal
    oled_write_cmd(0xA1); // Segment remap
    oled_write_cmd(0xC8); // COM scan direction
    oled_write_cmd(0xDA); // COM pins
    oled_write_cmd(0x02);
    oled_write_cmd(0x81); // Contrast
    oled_write_cmd(0x8F);
    oled_write_cmd(0xD9); // Pre-charge
    oled_write_cmd(0xF1);
    oled_write_cmd(0xDB); // VCOM detect
    oled_write_cmd(0x40);
    oled_write_cmd(0xA4); // Display resume
    oled_write_cmd(0xA6); // Normal display
    oled_write_cmd(0xAF); // Display on

    ESP_LOGI(TAG, "OLED initialized (128x32)");
}

void oled_clear(void)
{
    // Set column address range
    oled_write_cmd(0x21);
    oled_write_cmd(0x00); // Start
    oled_write_cmd(0x7F); // End (127)

    // Set page address range
    oled_write_cmd(0x22);
    oled_write_cmd(0x00); // Start
    oled_write_cmd(0x03); // End (3 pages for 32 rows)

    // Send 512 bytes of zeros (128 * 4)
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (OLED_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, 0x40, true); // Data mode

    for (int i = 0; i < 512; i++) {
        i2c_master_write_byte(cmd, 0x00, true);
    }

    i2c_master_stop(cmd);
    i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, pdMS_TO_TICKS(1000));
    i2c_cmd_link_delete(cmd);
}

// Simple 5x8 font for basic ASCII characters (space through 'z')
static const uint8_t font_5x8[][5] = {
    {0x00, 0x00, 0x00, 0x00, 0x00}, // space
    {0x00, 0x00, 0x5F, 0x00, 0x00}, // !
    {0x00, 0x07, 0x00, 0x07, 0x00}, // "
    {0x14, 0x7F, 0x14, 0x7F, 0x14}, // #
    {0x24, 0x2A, 0x7F, 0x2A, 0x12}, // $
    {0x23, 0x13, 0x08, 0x64, 0x62}, // %
    {0x36, 0x49, 0x55, 0x22, 0x50}, // &
    {0x00, 0x05, 0x03, 0x00, 0x00}, // '
    {0x00, 0x1C, 0x22, 0x41, 0x00}, // (
    {0x00, 0x41, 0x22, 0x1C, 0x00}, // )
    {0x08, 0x2A, 0x1C, 0x2A, 0x08}, // *
    {0x08, 0x08, 0x3E, 0x08, 0x08}, // +
    {0x00, 0x50, 0x30, 0x00, 0x00}, // ,
    {0x08, 0x08, 0x08, 0x08, 0x08}, // -
    {0x00, 0x60, 0x60, 0x00, 0x00}, // .
    {0x20, 0x10, 0x08, 0x04, 0x02}, // /
    {0x3E, 0x51, 0x49, 0x45, 0x3E}, // 0
    {0x00, 0x42, 0x7F, 0x40, 0x00}, // 1
    {0x42, 0x61, 0x51, 0x49, 0x46}, // 2
    {0x21, 0x41, 0x45, 0x4B, 0x31}, // 3
    {0x18, 0x14, 0x12, 0x7F, 0x10}, // 4
    {0x27, 0x45, 0x45, 0x45, 0x39}, // 5
    {0x3C, 0x4A, 0x49, 0x49, 0x30}, // 6
    {0x01, 0x71, 0x09, 0x05, 0x03}, // 7
    {0x36, 0x49, 0x49, 0x49, 0x36}, // 8
    {0x06, 0x49, 0x49, 0x29, 0x1E}, // 9
    {0x00, 0x36, 0x36, 0x00, 0x00}, // :
    {0x00, 0x56, 0x36, 0x00, 0x00}, // ;
    {0x00, 0x08, 0x14, 0x22, 0x41}, // <
    {0x14, 0x14, 0x14, 0x14, 0x14}, // =
    {0x41, 0x22, 0x14, 0x08, 0x00}, // >
    {0x02, 0x01, 0x51, 0x09, 0x06}, // ?
    {0x32, 0x49, 0x79, 0x41, 0x3E}, // @
    {0x7E, 0x11, 0x11, 0x11, 0x7E}, // A
    {0x7F, 0x49, 0x49, 0x49, 0x36}, // B
    {0x3E, 0x41, 0x41, 0x41, 0x22}, // C
    {0x7F, 0x41, 0x41, 0x22, 0x1C}, // D
    {0x7F, 0x49, 0x49, 0x49, 0x41}, // E
    {0x7F, 0x09, 0x09, 0x01, 0x01}, // F
    {0x3E, 0x41, 0x41, 0x51, 0x32}, // G
    {0x7F, 0x08, 0x08, 0x08, 0x7F}, // H
    {0x00, 0x41, 0x7F, 0x41, 0x00}, // I
    {0x20, 0x40, 0x41, 0x3F, 0x01}, // J
    {0x7F, 0x08, 0x14, 0x22, 0x41}, // K
    {0x7F, 0x40, 0x40, 0x40, 0x40}, // L
    {0x7F, 0x02, 0x04, 0x02, 0x7F}, // M
    {0x7F, 0x04, 0x08, 0x10, 0x7F}, // N
    {0x3E, 0x41, 0x41, 0x41, 0x3E}, // O
    {0x7F, 0x09, 0x09, 0x09, 0x06}, // P
    {0x3E, 0x41, 0x51, 0x21, 0x5E}, // Q
    {0x7F, 0x09, 0x19, 0x29, 0x46}, // R
    {0x46, 0x49, 0x49, 0x49, 0x31}, // S
    {0x01, 0x01, 0x7F, 0x01, 0x01}, // T
    {0x3F, 0x40, 0x40, 0x40, 0x3F}, // U
    {0x1F, 0x20, 0x40, 0x20, 0x1F}, // V
    {0x7F, 0x20, 0x18, 0x20, 0x7F}, // W
    {0x63, 0x14, 0x08, 0x14, 0x63}, // X
    {0x03, 0x04, 0x78, 0x04, 0x03}, // Y
    {0x61, 0x51, 0x49, 0x45, 0x43}, // Z
    {0x00, 0x00, 0x7F, 0x41, 0x41}, // [
    {0x02, 0x04, 0x08, 0x10, 0x20}, // backslash
    {0x41, 0x41, 0x7F, 0x00, 0x00}, // ]
    {0x04, 0x02, 0x01, 0x02, 0x04}, // ^
    {0x40, 0x40, 0x40, 0x40, 0x40}, // _
    {0x00, 0x01, 0x02, 0x04, 0x00}, // `
    {0x20, 0x54, 0x54, 0x54, 0x78}, // a
    {0x7F, 0x48, 0x44, 0x44, 0x38}, // b
    {0x38, 0x44, 0x44, 0x44, 0x20}, // c
    {0x38, 0x44, 0x44, 0x48, 0x7F}, // d
    {0x38, 0x54, 0x54, 0x54, 0x18}, // e
    {0x08, 0x7E, 0x09, 0x01, 0x02}, // f
    {0x08, 0x14, 0x54, 0x54, 0x3C}, // g
    {0x7F, 0x08, 0x04, 0x04, 0x78}, // h
    {0x00, 0x44, 0x7D, 0x40, 0x00}, // i
    {0x20, 0x40, 0x44, 0x3D, 0x00}, // j
    {0x00, 0x7F, 0x10, 0x28, 0x44}, // k
    {0x00, 0x41, 0x7F, 0x40, 0x00}, // l
    {0x7C, 0x04, 0x18, 0x04, 0x78}, // m
    {0x7C, 0x08, 0x04, 0x04, 0x78}, // n
    {0x38, 0x44, 0x44, 0x44, 0x38}, // o
    {0x7C, 0x14, 0x14, 0x14, 0x08}, // p
    {0x08, 0x14, 0x14, 0x18, 0x7C}, // q
    {0x7C, 0x08, 0x04, 0x04, 0x08}, // r
    {0x48, 0x54, 0x54, 0x54, 0x20}, // s
    {0x04, 0x3F, 0x44, 0x40, 0x20}, // t
    {0x3C, 0x40, 0x40, 0x20, 0x7C}, // u
    {0x1C, 0x20, 0x40, 0x20, 0x1C}, // v
    {0x3C, 0x40, 0x30, 0x40, 0x3C}, // w
    {0x44, 0x28, 0x10, 0x28, 0x44}, // x
    {0x0C, 0x50, 0x50, 0x50, 0x3C}, // y
    {0x44, 0x64, 0x54, 0x4C, 0x44}, // z
};

void oled_write_char_2x(uint8_t x, uint8_t y, char c)
{
    if (c < ' ' || c > 'z') c = ' ';  // Replace invalid chars with space

    const uint8_t *font_data = font_5x8[c - ' '];

    // 2x scaling: each character becomes 10x16 pixels
    // We need to write to 2 pages (y and y+1)
    for (int page = 0; page < 2; page++) {
        // Set column address (x position)
        oled_write_cmd(0x21);
        oled_write_cmd(x);
        oled_write_cmd(x + 10);

        // Set page address
        oled_write_cmd(0x22);
        oled_write_cmd(y + page);
        oled_write_cmd(y + page);

        // Write character bitmap with 2x scaling
        i2c_cmd_handle_t cmd = i2c_cmd_link_create();
        i2c_master_start(cmd);
        i2c_master_write_byte(cmd, (OLED_ADDR << 1) | I2C_MASTER_WRITE, true);
        i2c_master_write_byte(cmd, 0x40, true); // Data mode

        for (int col = 0; col < 5; col++) {
            uint8_t byte = font_data[col];
            uint8_t scaled = 0;

            // Scale vertically: take 4 bits from source, expand to 8 bits
            if (page == 0) {
                // Lower half of character (bits 0-3 become bits 0,0,2,2,4,4,6,6)
                for (int bit = 0; bit < 4; bit++) {
                    if (byte & (1 << bit)) {
                        scaled |= (3 << (bit * 2)); // Set 2 bits
                    }
                }
            } else {
                // Upper half of character (bits 4-7 become bits 0,0,2,2,4,4,6,6)
                for (int bit = 4; bit < 8; bit++) {
                    if (byte & (1 << bit)) {
                        scaled |= (3 << ((bit - 4) * 2)); // Set 2 bits
                    }
                }
            }

            // Write each column twice (horizontal scaling)
            i2c_master_write_byte(cmd, scaled, true);
            i2c_master_write_byte(cmd, scaled, true);
        }
        // Spacing
        i2c_master_write_byte(cmd, 0x00, true);

        i2c_master_stop(cmd);
        i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, pdMS_TO_TICKS(1000));
        i2c_cmd_link_delete(cmd);
    }
}

void oled_print(const char *text)
{
    oled_clear();

    // Write text starting at position (0, 0)
    // Each 2x character is 11 pixels wide (10 + 1 spacing)
    // 128 / 11 = ~11 characters per line
    uint8_t x = 0;
    uint8_t y = 0;

    for (int i = 0; text[i] != '\0' && x < 117; i++) {
        oled_write_char_2x(x, y, text[i]);
        x += 11;
    }

    ESP_LOGI(TAG, "OLED: %s", text);
}

void oled_write_char_1x(uint8_t x, uint8_t y, char c)
{
    if (c < ' ' || c > 'z') c = ' ';  // Replace invalid chars with space

    const uint8_t *font_data = font_5x8[c - ' '];

    // Set column address (x position)
    oled_write_cmd(0x21);
    oled_write_cmd(x);
    oled_write_cmd(x + 5);

    // Set page address (y position - each page is 8 pixels tall)
    oled_write_cmd(0x22);
    oled_write_cmd(y);
    oled_write_cmd(y);

    // Write character bitmap
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (OLED_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, 0x40, true); // Data mode

    for (int i = 0; i < 5; i++) {
        i2c_master_write_byte(cmd, font_data[i], true);
    }
    i2c_master_write_byte(cmd, 0x00, true); // 1 pixel spacing between chars

    i2c_master_stop(cmd);
    i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, pdMS_TO_TICKS(1000));
    i2c_cmd_link_delete(cmd);
}

void oled_write_char_2x_narrow(uint8_t x, uint8_t y, char c)
{
    if (c < ' ' || c > 'z') c = ' ';

    const uint8_t *font_data = font_5x8[c - ' '];

    // 2x vertical, 1x horizontal (narrow): 5 pixels wide, 16 pixels tall
    // This fits 128/6 = 21 characters but keeps text tall and readable
    for (int page = 0; page < 2; page++) {
        oled_write_cmd(0x21);
        oled_write_cmd(x);
        oled_write_cmd(x + 5);

        oled_write_cmd(0x22);
        oled_write_cmd(y + page);
        oled_write_cmd(y + page);

        i2c_cmd_handle_t cmd = i2c_cmd_link_create();
        i2c_master_start(cmd);
        i2c_master_write_byte(cmd, (OLED_ADDR << 1) | I2C_MASTER_WRITE, true);
        i2c_master_write_byte(cmd, 0x40, true);

        for (int col = 0; col < 5; col++) {
            uint8_t byte = font_data[col];
            uint8_t scaled = 0;

            // 2x vertical scaling only
            if (page == 0) {
                // Lower half (bits 0-3 become 0,0,2,2,4,4,6,6)
                for (int bit = 0; bit < 4; bit++) {
                    if (byte & (1 << bit)) {
                        scaled |= (3 << (bit * 2));
                    }
                }
            } else {
                // Upper half (bits 4-7 become 0,0,2,2,4,4,6,6)
                for (int bit = 4; bit < 8; bit++) {
                    if (byte & (1 << bit)) {
                        scaled |= (3 << ((bit - 4) * 2));
                    }
                }
            }

            // Write each column once (1x horizontal)
            i2c_master_write_byte(cmd, scaled, true);
        }
        // Small spacing
        i2c_master_write_byte(cmd, 0x00, true);

        i2c_master_stop(cmd);
        i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, pdMS_TO_TICKS(1000));
        i2c_cmd_link_delete(cmd);
    }
}

void oled_print_2lines(const char *line1, const char *line2)
{
    oled_clear();

    // Line 1 at page 0 (top half) - BIG text (2x scale)
    uint8_t x = 0;
    for (int i = 0; line1[i] != '\0' && x < 117; i++) {
        oled_write_char_2x(x, 0, line1[i]);
        x += 11;
    }

    // Line 2 at page 2 (bottom half) - TALL but NARROW text for IP addresses
    // 2x vertical, 1x horizontal = 6 pixels wide, fits 21 chars
    x = 0;
    for (int i = 0; line2[i] != '\0' && x < 122; i++) {
        oled_write_char_2x_narrow(x, 2, line2[i]);
        x += 6;
    }

    ESP_LOGI(TAG, "OLED: %s / %s", line1, line2);
}

// ============================================================================
// Antenna Configuration
// ============================================================================

void setup_external_antenna(void)
{
    // Configure GPIO38 to select external antenna (HIGH = external, LOW = internal)
    gpio_config_t antenna_conf = {
        .pin_bit_mask = (1ULL << ANTENNA_SELECT_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&antenna_conf);

    // Set HIGH to enable external antenna
    gpio_set_level(ANTENNA_SELECT_PIN, 1);

    ESP_LOGI(TAG, "External antenna enabled on GPIO%d (HIGH)", ANTENNA_SELECT_PIN);
}

// ============================================================================
// PIR Sensor
// ============================================================================

void setup_pir_sensor(void)
{
    gpio_config_t pir_conf = {
        .pin_bit_mask = (1ULL << PIR_PIN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&pir_conf);

    ESP_LOGI(TAG, "PIR sensor initialized on GPIO%d", PIR_PIN);
}

bool read_pir_sensor(void)
{
    return gpio_get_level(PIR_PIN);
}

// ============================================================================
// UART Communication with XIAO C6 Zigbee Coordinator
// ============================================================================

void setup_uart(void)
{
    uart_config_t uart_config = {
        .baud_rate = 115200,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    ESP_ERROR_CHECK(uart_driver_install(UART_NUM, UART_BUF_SIZE * 2, UART_BUF_SIZE * 2, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(UART_NUM, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(UART_NUM, UART_TX_PIN, UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    ESP_LOGI(TAG, "UART initialized (TX:%d, RX:%d) for XIAO C6 communication", UART_TX_PIN, UART_RX_PIN);
}

void uart_send_command(uint8_t cmd)
{
    uint8_t data[3] = {0xAA, cmd, 0x55}; // Simple framing: start, command, end
    uart_write_bytes(UART_NUM, data, sizeof(data));
    ESP_LOGI(TAG, "UART sent command: 0x%02x", cmd);
}

void uart_request_status(void)
{
    uart_send_command(CMD_STATUS_REQUEST);
}

// Task to request status updates every 3 seconds
void status_request_task(void *pvParameters)
{
    // Wait 2 seconds before first request
    vTaskDelay(pdMS_TO_TICKS(2000));

    while (1) {
        uart_request_status();
        vTaskDelay(pdMS_TO_TICKS(3000));  // Request every 3 seconds
    }
}

void trigger_rip_tombstone_uart(void)
{
    ESP_LOGI(TAG, "Triggering RIP Tombstone via UART");
    uart_send_command(CMD_TRIGGER_RIP);
    log_event(EVENT_TRIGGER_RIP, NULL);
}

void trigger_halloween_decoration_uart(void)
{
    ESP_LOGI(TAG, "Triggering Haunted Pumpkin Scarecrow via UART");
    uart_send_command(CMD_TRIGGER_HALLOWEEN);
    log_event(EVENT_TRIGGER_HALLOWEEN, NULL);
}

void trigger_both_uart(void)
{
    ESP_LOGI(TAG, "Triggering BOTH devices via UART");
    uart_send_command(CMD_TRIGGER_BOTH);
    log_event(EVENT_TRIGGER_BOTH, NULL);
}

void uart_send_time_sync(void)
{
    if (!time_synced) {
        ESP_LOGW(TAG, "Cannot send time sync - time not synchronized yet");
        return;
    }

    time_t now = time(NULL);

    // Frame: 0xAA CMD_TIME_SYNC timestamp(4 bytes) 0x55
    uint8_t data[7];
    data[0] = 0xAA;  // Start byte
    data[1] = CMD_TIME_SYNC;
    data[2] = (now >> 24) & 0xFF;  // Unix timestamp big-endian
    data[3] = (now >> 16) & 0xFF;
    data[4] = (now >> 8) & 0xFF;
    data[5] = now & 0xFF;
    data[6] = 0x55;  // End byte

    uart_write_bytes(UART_NUM, data, sizeof(data));

    ESP_LOGI(TAG, "UART sent time sync: %ld (Unix timestamp)", now);

    struct tm timeinfo;
    localtime_r(&now, &timeinfo);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
    ESP_LOGI(TAG, "   Time: %s", time_str);
}

// ============================================================================
// UART Receiver Task (for status updates from XIAO C6)
// ============================================================================

void uart_receiver_task(void *pvParameters)
{
    uint8_t data[16];

    ESP_LOGI(TAG, "UART receiver task started");

    while (1) {
        int len = uart_read_bytes(UART_NUM, data, sizeof(data), pdMS_TO_TICKS(100));

        if (len > 0) {
            // Look for status response frame: 0xAA CMD_STATUS_RESPONSE flags(2 bytes) 0x55
            for (int i = 0; i < len - 4; i++) {
                if (data[i] == 0xAA && data[i + 1] == CMD_STATUS_RESPONSE && data[i + 4] == 0x55) {
                    uint16_t flags = ((uint16_t)data[i + 2] << 8) | data[i + 3];

                    // Parse flags
                    bool rip_time_synced = (flags & (1 << 0)) != 0;
                    bool halloween_time_synced = (flags & (1 << 1)) != 0;
                    bool rip_connected = (flags & (1 << 2)) != 0;
                    bool halloween_connected = (flags & (1 << 3)) != 0;
                    bool rip_cooldown = (flags & (1 << 4)) != 0;
                    bool halloween_cooldown = (flags & (1 << 5)) != 0;

                    // Update device status
                    rip_tombstone.time_synced = rip_time_synced;
                    rip_tombstone.is_connected = rip_connected;
                    rip_tombstone.in_cooldown = rip_cooldown;
                    halloween_trigger.time_synced = halloween_time_synced;
                    halloween_trigger.is_connected = halloween_connected;
                    halloween_trigger.in_cooldown = halloween_cooldown;

                    ESP_LOGI(TAG, "Device status updated: RIP[%s/%s/%s] Halloween[%s/%s/%s]",
                             rip_connected ? "✓" : "✗",
                             rip_time_synced ? "✓" : "✗",
                             rip_cooldown ? "COOL" : "RDY",
                             halloween_connected ? "✓" : "✗",
                             halloween_time_synced ? "✓" : "✗",
                             halloween_cooldown ? "COOL" : "RDY");
                }
            }

            // Look for device join/leave notifications: 0xAA CMD device_id(1 byte) 0x55
            // device_id: 1 = RIP, 2 = Halloween
            for (int i = 0; i < len - 3; i++) {
                if (data[i] == 0xAA && data[i + 3] == 0x55) {
                    uint8_t cmd = data[i + 1];
                    uint8_t device_id = data[i + 2];

                    if (cmd == CMD_DEVICE_JOINED) {
                        const char *device_name = (device_id == 1) ? "RIP Tombstone" :
                                                 (device_id == 2) ? "Haunted Pumpkin Scarecrow" : "Unknown";
                        ESP_LOGI(TAG, "Device joined: %s", device_name);
                        log_event(EVENT_DEVICE_JOINED, device_name);
                    } else if (cmd == CMD_DEVICE_LEFT) {
                        const char *device_name = (device_id == 1) ? "RIP Tombstone" :
                                                 (device_id == 2) ? "Haunted Pumpkin Scarecrow" : "Unknown";
                        ESP_LOGI(TAG, "Device left: %s", device_name);
                        log_event(EVENT_DEVICE_LEFT, device_name);
                    }
                }
            }
        }
    }
}

// ============================================================================
// NTP Time Sync (Los Angeles timezone)
// ============================================================================

void time_sync_notification_cb(struct timeval *tv)
{
    ESP_LOGI(TAG, "✓ Time synchronized via NTP!");
    ESP_LOGI(TAG, "✓ Epoch time: %ld", tv->tv_sec);
    time_synced = true;
}

void initialize_sntp(void)
{
    ESP_LOGI(TAG, "Initializing SNTP for Los Angeles timezone");
    setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);
    tzset();

    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "192.168.5.1");
    sntp_set_time_sync_notification_cb(time_sync_notification_cb);

    esp_sntp_init();
    ESP_LOGI(TAG, "⏳ SNTP initialized, waiting for time sync...");
}

void get_current_time_str(char *buffer, size_t size)
{
    time_t now;
    struct tm timeinfo;
    time(&now);
    localtime_r(&now, &timeinfo);

    if (time_synced) {
        strftime(buffer, size, "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
    } else {
        snprintf(buffer, size, "Not synced");
    }
}

void wait_for_ntp_sync(uint32_t timeout_seconds)
{
    ESP_LOGI(TAG, "⏳ Waiting for NTP time synchronization...");
    ESP_LOGI(TAG, "   Timeout: %lu seconds", timeout_seconds);

    uint32_t elapsed = 0;
    while (!time_synced && elapsed < timeout_seconds) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        elapsed++;

        if (elapsed % 5 == 0) {
            ESP_LOGI(TAG, "   Still waiting for NTP sync... (%lu/%lu seconds)", elapsed, timeout_seconds);
        }
    }

    if (time_synced) {
        char time_str[64];
        get_current_time_str(time_str, sizeof(time_str));
        ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
        ESP_LOGI(TAG, "║  ✓ TIME SYNCHRONIZED                         ║");
        ESP_LOGI(TAG, "║  %s                ║", time_str);
        ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");
    } else {
        ESP_LOGE(TAG, "❌ FATAL ERROR: NTP TIME SYNC FAILED");
        ESP_LOGE(TAG, "   Timeout after %lu seconds", timeout_seconds);
        ESP_LOGE(TAG, "HALTING PROGRAM DUE TO NTP SYNC FAILURE");
        abort();
    }
}

// ============================================================================
// WiFi Event Handler
// ============================================================================

static void wifi_event_handler(void* arg, esp_event_base_t event_base,
                              int32_t event_id, void* event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        ESP_LOGI(TAG, "WiFi station started");

        // Disable WiFi power management EARLY to prevent WPA3 SA Query timeout
        // and ensure network stack is fully functional
        esp_wifi_set_ps(WIFI_PS_NONE);
        ESP_LOGI(TAG, "🔋 WiFi power management disabled (prevents WPA3 SA Query timeouts)");

        // Don't connect here - let wifi_init_sta() handle initial connection
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t* disconnected = (wifi_event_sta_disconnected_t*) event_data;
        ESP_LOGW(TAG, "WiFi disconnected, reason: %d", disconnected->reason);

        s_retry_num++;
        ESP_LOGI(TAG, "Reconnecting to WiFi (attempt %d)...", s_retry_num);
        vTaskDelay(pdMS_TO_TICKS(1000));
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "✓ WiFi connected successfully!");
        ESP_LOGI(TAG, "✓ IP Address: " IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "✓ Netmask:    " IPSTR, IP2STR(&event->ip_info.netmask));
        ESP_LOGI(TAG, "✓ Gateway:    " IPSTR, IP2STR(&event->ip_info.gw));

        // Save IP address for display
        snprintf(wifi_ip, sizeof(wifi_ip), IPSTR, IP2STR(&event->ip_info.ip));

        // Get WiFi info including MAC address
        wifi_ap_record_t ap_info;
        if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK) {
            ESP_LOGI(TAG, "✓ Connected to AP: %s", ap_info.ssid);
            ESP_LOGI(TAG, "✓ AP MAC (BSSID): %02x:%02x:%02x:%02x:%02x:%02x",
                     ap_info.bssid[0], ap_info.bssid[1], ap_info.bssid[2],
                     ap_info.bssid[3], ap_info.bssid[4], ap_info.bssid[5]);
            ESP_LOGI(TAG, "✓ RSSI: %d dBm", ap_info.rssi);
            ESP_LOGI(TAG, "✓ Channel: %d", ap_info.primary);

            // Save WiFi info for display
            strncpy(wifi_ssid, (char*)ap_info.ssid, sizeof(wifi_ssid) - 1);
            wifi_ssid[sizeof(wifi_ssid) - 1] = '\0';
            wifi_rssi = ap_info.rssi;
        }

        // Get our own MAC address
        uint8_t mac[6];
        esp_wifi_get_mac(WIFI_IF_STA, mac);
        ESP_LOGI(TAG, "✓ Device MAC:     %02x:%02x:%02x:%02x:%02x:%02x",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

        s_retry_num = 0;
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

void wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_LOGI(TAG, "🔧 Initializing WiFi...");
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_t *sta_netif = esp_netif_create_default_wifi_sta();

    // Set hostname for DHCP
    ESP_ERROR_CHECK(esp_netif_set_hostname(sta_netif, "zigbeeween-tinys3"));
    ESP_LOGI(TAG, "📛 Hostname set to: zigbeeween-tinys3");

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_t instance_got_ip;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
                                                        ESP_EVENT_ANY_ID,
                                                        &wifi_event_handler,
                                                        NULL,
                                                        &instance_any_id));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT,
                                                        IP_EVENT_STA_GOT_IP,
                                                        &wifi_event_handler,
                                                        NULL,
                                                        &instance_got_ip));

    ESP_LOGI(TAG, "📶 Target SSID: '%s'", WIFI_SSID);
    ESP_LOGI(TAG, "🔑 Password: %s", strlen(WIFI_PASS) > 0 ? "[configured]" : "[EMPTY!]");

    wifi_config_t wifi_config = {
        .sta = {
            .ssid = WIFI_SSID,
            .password = WIFI_PASS,
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
            .scan_method = WIFI_ALL_CHANNEL_SCAN,
            .sort_method = WIFI_CONNECT_AP_BY_SIGNAL,
        },
    };

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));

    ESP_LOGI(TAG, "📡 Note: ESP32-S3 supports both 2.4GHz and 5GHz WiFi");
    ESP_LOGI(TAG, "🔌 Starting WiFi and connecting to '%s'...", WIFI_SSID);

    // Start WiFi
    ESP_ERROR_CHECK(esp_wifi_start());

    // Wait for WiFi to initialize
    vTaskDelay(pdMS_TO_TICKS(200));

    // Disconnect to stop auto-connect so we can scan
    esp_wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(100));

    // Scan for available networks (helps WiFi find APs)
    ESP_LOGI(TAG, "📡 Scanning for WiFi networks...");
    wifi_scan_config_t scan_config = {
        .ssid = NULL,
        .bssid = NULL,
        .channel = 0,
        .show_hidden = true,
        .scan_type = WIFI_SCAN_TYPE_ACTIVE
    };
    ESP_ERROR_CHECK(esp_wifi_scan_start(&scan_config, true));

    uint16_t ap_count = 0;
    esp_wifi_scan_get_ap_num(&ap_count);
    ESP_LOGI(TAG, "Found %d WiFi networks", ap_count);

    if (ap_count > 0) {
        wifi_ap_record_t *ap_list = malloc(sizeof(wifi_ap_record_t) * ap_count);
        if (ap_list != NULL) {
            ESP_ERROR_CHECK(esp_wifi_scan_get_ap_records(&ap_count, ap_list));

            ESP_LOGI(TAG, "╔══════════════════════════════════════════════════════════════════╗");
            ESP_LOGI(TAG, "║  #  SSID                          Ch  Band   RSSI  Auth         ║");
            ESP_LOGI(TAG, "╠══════════════════════════════════════════════════════════════════╣");

            for (int i = 0; i < ap_count && i < 15; i++) {
                const char *auth_mode;
                switch (ap_list[i].authmode) {
                    case WIFI_AUTH_OPEN: auth_mode = "OPEN"; break;
                    case WIFI_AUTH_WEP: auth_mode = "WEP"; break;
                    case WIFI_AUTH_WPA_PSK: auth_mode = "WPA-PSK"; break;
                    case WIFI_AUTH_WPA2_PSK: auth_mode = "WPA2-PSK"; break;
                    case WIFI_AUTH_WPA_WPA2_PSK: auth_mode = "WPA/WPA2"; break;
                    case WIFI_AUTH_WPA3_PSK: auth_mode = "WPA3-PSK"; break;
                    case WIFI_AUTH_WPA2_WPA3_PSK: auth_mode = "WPA2/WPA3"; break;
                    default: auth_mode = "UNKNOWN"; break;
                }

                const char *band = (ap_list[i].primary <= 14) ? "2.4G" : "5G";

                ESP_LOGI(TAG, "║ %2d  %-30s %3d  %-5s %4d  %-11s ║",
                         i + 1, ap_list[i].ssid, ap_list[i].primary, band,
                         ap_list[i].rssi, auth_mode);
            }

            ESP_LOGI(TAG, "╚══════════════════════════════════════════════════════════════════╝");
            free(ap_list);
        }
    }

    // Now attempt connection
    ESP_LOGI(TAG, "⏳ Connecting to '%s' (will retry forever)...", WIFI_SSID);
    esp_wifi_connect();
    xEventGroupWaitBits(s_wifi_event_group,
            WIFI_CONNECTED_BIT,
            pdFALSE,
            pdFALSE,
            portMAX_DELAY);

    ESP_LOGI(TAG, "✓✓✓ Successfully connected to WiFi SSID: %s", WIFI_SSID);
}

// ============================================================================
// HTTP Web Server Handlers
// ============================================================================

static esp_err_t root_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "HTTP GET /");

    char time_str[64];
    get_current_time_str(time_str, sizeof(time_str));

    httpd_resp_set_type(req, "text/html; charset=utf-8");

    // Send HTML in chunks
    httpd_resp_sendstr_chunk(req,
        "<!DOCTYPE html><html><head>"
        "<meta charset='utf-8'>"
        "<title>Zigbee Halloween Controller</title>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<style>"
        "body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px;text-align:center}"
        "h1{color:#ff6b00}h2{color:#ff8c00}"
        ".status{background:#2a2a2a;padding:15px;margin:20px 0;border-radius:10px}"
        ".status p{margin:8px 0}"
        ".button{background:#ff6b00;color:#fff;border:none;padding:15px 30px;font-size:18px;"
        "margin:10px;border-radius:5px;cursor:pointer;min-width:200px}"
        ".button:hover{background:#ff8c00}"
        ".button:active{background:#cc5500}"
        ".motion{color:#00ff00;font-weight:bold}"
        ".time{color:#88aaff;font-size:14px}"
        ".arch{color:#888;font-size:12px;margin-top:20px}"
        "#rip-status b,#halloween-status b{font-size:16px}"
        ".events{background:#2a2a2a;padding:15px;margin:20px 0;border-radius:10px;max-height:300px;overflow-y:auto;text-align:left}"
        ".events h3{text-align:center;margin-top:0;color:#ff8c00}"
        ".event{padding:5px 0;border-bottom:1px solid #444;font-size:13px}"
        ".event:last-child{border-bottom:none}"
        ".event-time{color:#88aaff;margin-right:10px}"
        ".event-type{color:#ffa500}"
        ".event-device{color:#aaa;margin-left:5px}"
        "</style></head><body>"
        "<h1>🎃 Zigbee Halloween Controller 🎃</h1>"
        "<div class='status'>");

    char buf[128];
    snprintf(buf, sizeof(buf), "<p class='time'>%s</p>", time_str);
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p>PIR Motion: <span class='motion' id='motion-status'>%s</span></p>",
             pir_motion_detected ? "DETECTED" : "None");
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p id='rip-status'>RIP Tombstone: %s | Time: %s | <b>%s</b></p>",
             rip_tombstone.is_connected ? "✓ Connected" : "✗ Not connected",
             rip_tombstone.time_synced ? "✓ Synced" : "✗ Not synced",
             rip_tombstone.in_cooldown ? "COOLDOWN" : "READY");
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p id='halloween-status'>Haunted Pumpkin Scarecrow: %s | Time: %s | <b>%s</b></p>",
             halloween_trigger.is_connected ? "✓ Connected" : "✗ Not connected",
             halloween_trigger.time_synced ? "✓ Synced" : "✗ Not synced",
             halloween_trigger.in_cooldown ? "COOLDOWN" : "READY");
    httpd_resp_sendstr_chunk(req, buf);

    httpd_resp_sendstr_chunk(req,
        "</div>"
        "<div class='events'>"
        "<h3>Event Log</h3>"
        "<div id='event-log'></div>"
        "</div>"
        "<h2>Manual Control</h2>"
        "<form method='POST' action='/trigger/rip'>"
        "<button class='button' type='submit'>🪦 Trigger RIP Tombstone</button>"
        "</form>"
        "<form method='POST' action='/trigger/halloween'>"
        "<button class='button' type='submit'>🎃 Trigger Pumpkin Scarecrow</button>"
        "</form>"
        "<form method='POST' action='/trigger/both'>"
        "<button class='button' type='submit'>👻 Trigger BOTH</button>"
        "</form>"
        "<p class='arch'>TinyS3 (ESP32-S3) + XIAO C6 (Zigbee) via UART</p>"
        "<script>"
        "function getEventLabel(type){"
            "const labels={'motion_detected':'🟢 Motion Detected','motion_stopped':'⚫ Motion Stopped',"
            "'trigger_rip':'🪦 Trigger RIP','trigger_halloween':'🎃 Trigger Pumpkin Scarecrow',"
            "'trigger_both':'👻 Trigger Both','device_joined':'✓ Device Joined','device_left':'✗ Device Left'};"
            "return labels[type]||type;"
        "}"
        "function updateStatus(){"
            "fetch('/api/status')"
            ".then(r=>r.json())"
            ".then(d=>{"
                "document.querySelector('.time').textContent=d.time;"
                "document.getElementById('motion-status').textContent=d.pir_motion?'DETECTED':'None';"
                "document.getElementById('rip-status').innerHTML='RIP Tombstone: '+(d.rip_tombstone.connected?'✓ Connected':'✗ Not connected')+' | Time: '+(d.rip_tombstone.time_synced?'✓ Synced':'✗ Not synced')+' | <b>'+(d.rip_tombstone.in_cooldown?'COOLDOWN':'READY')+'</b>';"
                "document.getElementById('halloween-status').innerHTML='Haunted Pumpkin Scarecrow: '+(d.halloween_trigger.connected?'✓ Connected':'✗ Not connected')+' | Time: '+(d.halloween_trigger.time_synced?'✓ Synced':'✗ Not synced')+' | <b>'+(d.halloween_trigger.in_cooldown?'COOLDOWN':'READY')+'</b>';"
                "let eventsHtml='';"
                "if(d.events&&d.events.length>0){"
                    "d.events.forEach(e=>{"
                        "eventsHtml+='<div class=\"event\"><span class=\"event-time\">'+e.time+'</span>';"
                        "eventsHtml+='<span class=\"event-type\">'+getEventLabel(e.type)+'</span>';"
                        "if(e.device)eventsHtml+='<span class=\"event-device\">- '+e.device+'</span>';"
                        "eventsHtml+='</div>';"
                    "});"
                "}else{"
                    "eventsHtml='<div style=\"color:#888;text-align:center\">No events yet</div>';"
                "}"
                "document.getElementById('event-log').innerHTML=eventsHtml;"
            "})"
            ".catch(e=>console.error('Status update failed:',e));"
        "}"
        "updateStatus();"  // Update immediately on load
        "setInterval(updateStatus,2000);"  // Update every 2 seconds
        "</script>"
        "</body></html>");

    httpd_resp_sendstr_chunk(req, NULL);
    return ESP_OK;
}

static esp_err_t trigger_rip_handler(httpd_req_t *req)
{
    trigger_rip_tombstone_uart();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static esp_err_t trigger_halloween_handler(httpd_req_t *req)
{
    trigger_halloween_decoration_uart();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static esp_err_t trigger_both_handler(httpd_req_t *req)
{
    trigger_both_uart();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static esp_err_t status_json_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "HTTP GET /api/status");

    char time_str[64];
    get_current_time_str(time_str, sizeof(time_str));

    httpd_resp_set_type(req, "application/json");

    // Start building JSON (use chunked sending for large responses)
    httpd_resp_sendstr_chunk(req, "{");

    // Current status
    char buf[512];
    snprintf(buf, sizeof(buf),
        "\"time\":\"%s\","
        "\"pir_motion\":%s,"
        "\"rip_tombstone\":{"
            "\"connected\":%s,"
            "\"time_synced\":%s,"
            "\"in_cooldown\":%s"
        "},"
        "\"halloween_trigger\":{"
            "\"connected\":%s,"
            "\"time_synced\":%s,"
            "\"in_cooldown\":%s"
        "},",
        time_str,
        pir_motion_detected ? "true" : "false",
        rip_tombstone.is_connected ? "true" : "false",
        rip_tombstone.time_synced ? "true" : "false",
        rip_tombstone.in_cooldown ? "true" : "false",
        halloween_trigger.is_connected ? "true" : "false",
        halloween_trigger.time_synced ? "true" : "false",
        halloween_trigger.in_cooldown ? "true" : "false"
    );
    httpd_resp_sendstr_chunk(req, buf);

    // Event log (last 20 events, newest first)
    httpd_resp_sendstr_chunk(req, "\"events\":[");

    int events_to_show = (event_log_count < 20) ? event_log_count : 20;
    for (int i = 0; i < events_to_show; i++) {
        // Calculate index (newest first)
        int idx = (event_log_head - 1 - i + MAX_EVENTS) % MAX_EVENTS;
        if (idx < 0 || idx >= event_log_count) continue;

        const char *event_type;
        switch (event_log[idx].type) {
            case EVENT_MOTION_DETECTED: event_type = "motion_detected"; break;
            case EVENT_MOTION_STOPPED: event_type = "motion_stopped"; break;
            case EVENT_TRIGGER_RIP: event_type = "trigger_rip"; break;
            case EVENT_TRIGGER_HALLOWEEN: event_type = "trigger_halloween"; break;
            case EVENT_TRIGGER_BOTH: event_type = "trigger_both"; break;
            case EVENT_DEVICE_JOINED: event_type = "device_joined"; break;
            case EVENT_DEVICE_LEFT: event_type = "device_left"; break;
            default: event_type = "unknown"; break;
        }

        struct tm timeinfo;
        localtime_r(&event_log[idx].timestamp, &timeinfo);
        char event_time[32];
        strftime(event_time, sizeof(event_time), "%H:%M:%S", &timeinfo);

        if (event_log[idx].device_name[0] != '\0') {
            snprintf(buf, sizeof(buf), "%s{\"time\":\"%s\",\"type\":\"%s\",\"device\":\"%s\"}",
                     (i > 0) ? "," : "", event_time, event_type, event_log[idx].device_name);
        } else {
            snprintf(buf, sizeof(buf), "%s{\"time\":\"%s\",\"type\":\"%s\"}",
                     (i > 0) ? "," : "", event_time, event_type);
        }
        httpd_resp_sendstr_chunk(req, buf);
    }

    httpd_resp_sendstr_chunk(req, "]}");
    httpd_resp_sendstr_chunk(req, NULL);
    return ESP_OK;
}

httpd_handle_t start_webserver(void)
{
    httpd_handle_t server = NULL;
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.lru_purge_enable = true;

    if (httpd_start(&server, &config) == ESP_OK) {
        httpd_uri_t root = {.uri = "/", .method = HTTP_GET, .handler = root_handler};
        httpd_register_uri_handler(server, &root);

        httpd_uri_t status_json = {.uri = "/api/status", .method = HTTP_GET, .handler = status_json_handler};
        httpd_register_uri_handler(server, &status_json);

        httpd_uri_t trigger_rip = {.uri = "/trigger/rip", .method = HTTP_POST, .handler = trigger_rip_handler};
        httpd_register_uri_handler(server, &trigger_rip);

        httpd_uri_t trigger_halloween = {.uri = "/trigger/halloween", .method = HTTP_POST, .handler = trigger_halloween_handler};
        httpd_register_uri_handler(server, &trigger_halloween);

        httpd_uri_t trigger_both = {.uri = "/trigger/both", .method = HTTP_POST, .handler = trigger_both_handler};
        httpd_register_uri_handler(server, &trigger_both);

        ESP_LOGI(TAG, "✓ HTTP server started successfully!");
        return server;
    }

    ESP_LOGE(TAG, "❌ Error starting HTTP server!");
    return NULL;
}

// ============================================================================
// PIR Monitoring Task
// ============================================================================

void pir_monitor_task(void *pvParameters)
{
    bool last_motion = false;

    ESP_LOGI(TAG, "PIR monitoring task started");

    while (1) {
        bool current_motion = read_pir_sensor();

        if (current_motion != last_motion) {
            pir_motion_detected = current_motion;

            if (current_motion) {
                ESP_LOGI(TAG, "🟢 Motion detected!");
                log_event(EVENT_MOTION_DETECTED, NULL);
                oled_print_2lines("MOTION!", "DETECTED");

                // Auto-trigger via UART to XIAO C6 (intelligently trigger based on connected devices)
                bool rip_ready = rip_tombstone.is_connected;
                bool halloween_ready = halloween_trigger.is_connected;

                if (rip_ready && halloween_ready) {
                    trigger_both_uart();
                } else if (halloween_ready) {
                    trigger_halloween_decoration_uart();
                } else if (rip_ready) {
                    trigger_rip_tombstone_uart();
                } else {
                    ESP_LOGW(TAG, "Motion detected but no devices connected!");
                }
            } else {
                ESP_LOGI(TAG, "⚫ Motion stopped");
                log_event(EVENT_MOTION_STOPPED, NULL);
                // Return to showing WiFi status
                oled_print_2lines(wifi_ssid, wifi_ip);
            }

            last_motion = current_motion;
        }

        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

// ============================================================================
// Main Application
// ============================================================================

void app_main(void)
{
    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  Zigbee Halloween Controller - TinyS3        ║");
    ESP_LOGI(TAG, "║  ESP32-S3 WiFi/HTTP + XIAO C6 Zigbee         ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize hardware
    setup_external_antenna();  // Configure external antenna BEFORE WiFi init
    setup_i2c();
    oled_init();
    oled_print("Starting...");
    setup_pir_sensor();
    setup_uart();

    // Initialize WiFi
    ESP_LOGI(TAG, "Connecting to WiFi...");
    oled_print("WiFi...");
    wifi_init_sta();

    // Allow network stack to stabilize
    vTaskDelay(pdMS_TO_TICKS(2000));

    // Initialize NTP and wait for sync
    initialize_sntp();
    oled_print("Time sync...");
    wait_for_ntp_sync(60);

    // Send time to XIAO C6 over UART
    ESP_LOGI(TAG, "Synchronizing time with XIAO C6 Zigbee coordinator...");
    uart_send_time_sync();

    // Start web server
    ESP_LOGI(TAG, "Starting web server...");
    oled_print("Web server...");
    server = start_webserver();

    if (server) {
        esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
        esp_netif_ip_info_t ip_info;
        esp_netif_get_ip_info(netif, &ip_info);

        ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
        ESP_LOGI(TAG, "║  Web Interface Ready!                        ║");
        ESP_LOGI(TAG, "║  URL: http://" IPSTR "/               ║", IP2STR(&ip_info.ip));
        ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");
    }

    // Start UART receiver task to get device status from XIAO C6
    xTaskCreate(uart_receiver_task, "UART_receiver", 4096, NULL, 5, NULL);

    // Start status request task (polls coordinator every 3 seconds)
    xTaskCreate(status_request_task, "status_request", 4096, NULL, 4, NULL);
    ESP_LOGI(TAG, "Status request task started (polls every 3 seconds)");

    // Start PIR monitoring (increased stack size for UART + I2C operations)
    xTaskCreate(pir_monitor_task, "PIR_monitor", 4096, NULL, 4, NULL);

    // Request initial device status from XIAO C6
    vTaskDelay(pdMS_TO_TICKS(1000));
    uart_request_status();

    // Display ready message
    vTaskDelay(pdMS_TO_TICKS(1000));
    oled_print_2lines(wifi_ssid, wifi_ip);

    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  System Ready!                               ║");
    ESP_LOGI(TAG, "║  - WiFi + HTTP server active                 ║");
    ESP_LOGI(TAG, "║  - PIR motion detection enabled              ║");
    ESP_LOGI(TAG, "║  - UART to XIAO C6 Zigbee coordinator        ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Main loop
    uint32_t time_sync_counter = 0;
    uint32_t oled_update_counter = 0;
    const uint32_t TIME_SYNC_INTERVAL = 3600; // Sync time every hour (3600 seconds)
    const uint32_t OLED_UPDATE_INTERVAL = 10;  // Update OLED every 10 seconds

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));  // Check every 1 second

        char time_str[64];
        get_current_time_str(time_str, sizeof(time_str));

        // Log status every 5 seconds
        if (time_sync_counter % 5 == 0) {
            ESP_LOGI(TAG, "Time: %s, Motion: %s",
                     time_str,
                     pir_motion_detected ? "YES" : "NO");
        }

        // Update OLED display with WiFi status every 10 seconds (unless motion detected)
        oled_update_counter++;
        if (oled_update_counter >= OLED_UPDATE_INTERVAL && !pir_motion_detected) {
            // Show WiFi SSID and IP address
            oled_print_2lines(wifi_ssid, wifi_ip);
            oled_update_counter = 0;
        }

        // Periodically sync time with XIAO C6 (every hour)
        time_sync_counter++;
        if (time_sync_counter >= TIME_SYNC_INTERVAL) {
            ESP_LOGI(TAG, "Periodic time sync with XIAO C6...");
            uart_send_time_sync();
            time_sync_counter = 0;
        }
    }
}
