#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "nvs_flash.h"
#include "esp_zigbee_core.h"
#include "esp_sleep.h"

static const char *TAG = "zigbee_halloween";

// Pin definitions
#define TRIGGER_PIN GPIO_NUM_18  // Pin to trigger the "try me" button (controls transistor/relay)
#define LED_PIN GPIO_NUM_15      // Built-in yellow LED on Xiao ESP32-C6
#define I2C_SDA_PIN GPIO_NUM_6   // I2C SDA for DS3231 RTC
#define I2C_SCL_PIN GPIO_NUM_7   // I2C SCL for DS3231 RTC

// I2C configuration
#define I2C_MASTER_NUM I2C_NUM_0
#define I2C_MASTER_FREQ_HZ 100000
#define DS3231_ADDR 0x68

// Trigger duration
#define TRIGGER_DURATION_MS 500  // Hold the "try me" button for 500ms

// Sleep hours (12am to 6am)
#define SLEEP_START_HOUR 0
#define SLEEP_END_HOUR 6

// Zigbee configuration
#define ESP_ZB_PRIMARY_CHANNEL_MASK ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK

static bool triggered_recently = false;

// DS3231 RTC functions
typedef struct {
    uint8_t second;
    uint8_t minute;
    uint8_t hour;
    uint8_t day;
    uint8_t month;
    uint8_t year;
} rtc_time_t;

// Convert BCD to decimal
static uint8_t bcd_to_dec(uint8_t val)
{
    return (val / 16 * 10) + (val % 16);
}

// Convert decimal to BCD
static uint8_t dec_to_bcd(uint8_t val)
{
    return (val / 10 * 16) + (val % 10);
}

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

    ESP_LOGI(TAG, "I2C initialized for DS3231 RTC");
}

esp_err_t ds3231_read_time(rtc_time_t *time)
{
    uint8_t data[7];

    // Read 7 bytes starting from register 0x00
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (DS3231_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, 0x00, true);  // Start at seconds register
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (DS3231_ADDR << 1) | I2C_MASTER_READ, true);
    i2c_master_read(cmd, data, 7, I2C_MASTER_LAST_NACK);
    i2c_master_stop(cmd);

    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, pdMS_TO_TICKS(1000));
    i2c_cmd_link_delete(cmd);

    if (ret == ESP_OK) {
        time->second = bcd_to_dec(data[0] & 0x7F);
        time->minute = bcd_to_dec(data[1] & 0x7F);
        time->hour = bcd_to_dec(data[2] & 0x3F);  // 24-hour format
        time->day = bcd_to_dec(data[4] & 0x3F);
        time->month = bcd_to_dec(data[5] & 0x1F);
        time->year = bcd_to_dec(data[6]);
    }

    return ret;
}

bool is_sleep_time(void)
{
    rtc_time_t time;

    if (ds3231_read_time(&time) == ESP_OK) {
        ESP_LOGI(TAG, "Current time: %02d:%02d:%02d", time.hour, time.minute, time.second);

        // Check if between 12am (0) and 6am
        if (time.hour >= SLEEP_START_HOUR && time.hour < SLEEP_END_HOUR) {
            ESP_LOGI(TAG, "Sleep time detected (12am-6am)");
            return true;
        }
    } else {
        ESP_LOGI(TAG, "Failed to read RTC time, assuming awake hours");
    }

    return false;
}

void setup_trigger_pin(void)
{
    gpio_config_t trigger_conf = {
        .pin_bit_mask = (1ULL << TRIGGER_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&trigger_conf);
    gpio_set_level(TRIGGER_PIN, 0);

    ESP_LOGI(TAG, "Trigger pin initialized on GPIO%d", TRIGGER_PIN);
}

void setup_led(void)
{
    gpio_config_t led_conf = {
        .pin_bit_mask = (1ULL << LED_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&led_conf);
    gpio_set_level(LED_PIN, 0);

    ESP_LOGI(TAG, "Yellow LED initialized on GPIO%d", LED_PIN);
}

void trigger_button(void)
{
    if (triggered_recently) {
        ESP_LOGI(TAG, "Ignoring trigger - recently activated");
        return;
    }

    ESP_LOGI(TAG, "🎃 TRIGGERING HALLOWEEN DECORATION!");

    // Turn on LED
    gpio_set_level(LED_PIN, 1);

    // Activate trigger pin (pull low to activate transistor/relay)
    gpio_set_level(TRIGGER_PIN, 1);

    // Hold for duration
    vTaskDelay(pdMS_TO_TICKS(TRIGGER_DURATION_MS));

    // Deactivate trigger pin
    gpio_set_level(TRIGGER_PIN, 0);

    // Turn off LED
    gpio_set_level(LED_PIN, 0);

    ESP_LOGI(TAG, "Trigger complete");

    // Set cooldown
    triggered_recently = true;

    // Reset cooldown after 5 seconds
    vTaskDelay(pdMS_TO_TICKS(5000));
    triggered_recently = false;
}

// Zigbee attribute handler
static esp_err_t zb_attribute_handler(const esp_zb_zcl_set_attr_value_message_t *message)
{
    esp_err_t ret = ESP_OK;

    ESP_LOGI(TAG, "Zigbee attribute update - Endpoint: %d, Cluster: 0x%04x, Attr: 0x%04x",
             message->info.dst_endpoint,
             message->info.cluster,
             message->attribute.id);

    // Check for On/Off cluster (0x0006)
    if (message->info.cluster == ESP_ZB_ZCL_CLUSTER_ID_ON_OFF) {
        if (message->attribute.id == ESP_ZB_ZCL_ATTR_ON_OFF_ON_OFF_ID) {
            uint8_t value = *(uint8_t *)message->attribute.data.value;

            ESP_LOGI(TAG, "Received On/Off command: %s", value ? "ON" : "OFF");

            if (value) {
                // Trigger the Halloween decoration
                trigger_button();
            }
        }
    }

    return ret;
}

static void esp_zb_task(void *pvParameters)
{
    esp_zb_cfg_t zb_nwk_cfg = ESP_ZB_ZED_CONFIG();
    esp_zb_init(&zb_nwk_cfg);

    // Create endpoint list
    esp_zb_ep_list_t *ep_list = esp_zb_ep_list_create();

    // Create cluster list for endpoint 1
    esp_zb_cluster_list_t *cluster_list = esp_zb_zcl_cluster_list_create();

    // Add basic cluster
    esp_zb_attribute_list_t *basic_cluster = esp_zb_basic_cluster_create(NULL);
    esp_zb_cluster_list_add_basic_cluster(cluster_list, basic_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Add identify cluster
    esp_zb_attribute_list_t *identify_cluster = esp_zb_identify_cluster_create(NULL);
    esp_zb_cluster_list_add_identify_cluster(cluster_list, identify_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Add on/off cluster
    esp_zb_on_off_cluster_cfg_t on_off_cfg = {
        .on_off = ESP_ZB_ZCL_ON_OFF_ON_OFF_DEFAULT_VALUE,
    };
    esp_zb_attribute_list_t *on_off_cluster = esp_zb_on_off_cluster_create(&on_off_cfg);
    esp_zb_cluster_list_add_on_off_cluster(cluster_list, on_off_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Create endpoint
    esp_zb_endpoint_config_t endpoint_config = {
        .endpoint = 1,
        .app_profile_id = ESP_ZB_AF_HA_PROFILE_ID,
        .app_device_id = ESP_ZB_HA_ON_OFF_OUTPUT_DEVICE_ID,
        .app_device_version = 0
    };
    esp_zb_ep_list_add_ep(ep_list, cluster_list, endpoint_config);

    esp_zb_device_register(ep_list);

    // Set attribute handler
    esp_zb_core_action_handler_register(zb_attribute_handler);

    ESP_LOGI(TAG, "Starting Zigbee stack");
    ESP_ERROR_CHECK(esp_zb_start(false));
    esp_zb_main_loop_iteration();
}

void enter_deep_sleep(void)
{
    ESP_LOGI(TAG, "Entering deep sleep until 6am...");

    // Calculate sleep duration (until 6am)
    rtc_time_t current_time;
    if (ds3231_read_time(&current_time) == ESP_OK) {
        int hours_until_wakeup = SLEEP_END_HOUR - current_time.hour;
        if (hours_until_wakeup < 0) {
            hours_until_wakeup += 24;
        }

        int minutes_until_wakeup = 60 - current_time.minute;
        int total_seconds = (hours_until_wakeup * 3600) - (current_time.minute * 60) - current_time.second;

        ESP_LOGI(TAG, "Sleeping for %d seconds (%d hours)", total_seconds, hours_until_wakeup);

        // Configure timer wakeup
        esp_sleep_enable_timer_wakeup(total_seconds * 1000000ULL);  // microseconds

        // Turn off LED before sleep
        gpio_set_level(LED_PIN, 0);

        // Enter deep sleep
        esp_deep_sleep_start();
    } else {
        ESP_LOGE(TAG, "Failed to read RTC, sleeping for 6 hours");
        esp_sleep_enable_timer_wakeup(6 * 60 * 60 * 1000000ULL);
        esp_deep_sleep_start();
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "Zigbee Halloween Trigger - Xiao ESP32-C6");
    ESP_LOGI(TAG, "Chip: ESP32-C6 (RISC-V)");
    ESP_LOGI(TAG, "Zigbee-controlled Halloween decoration trigger with RTC sleep");
    ESP_LOGI(TAG, "Active hours: 6am-12am, Sleep: 12am-6am");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize hardware
    setup_trigger_pin();
    setup_led();
    setup_i2c();

    // Check if it's sleep time
    if (is_sleep_time()) {
        enter_deep_sleep();
        // This line will never be reached
    }

    ESP_LOGI(TAG, "Active hours - Starting Zigbee");

    // Flash LED to indicate startup
    for (int i = 0; i < 3; i++) {
        gpio_set_level(LED_PIN, 1);
        vTaskDelay(pdMS_TO_TICKS(100));
        gpio_set_level(LED_PIN, 0);
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    // Start Zigbee
    xTaskCreate(esp_zb_task, "Zigbee_main", 4096, NULL, 5, NULL);

    // Periodic sleep check task
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(60000));  // Check every minute

        if (is_sleep_time()) {
            enter_deep_sleep();
        }
    }
}
