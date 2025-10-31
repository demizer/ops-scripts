#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#include "nvs_flash.h"
#include "esp_zigbee_core.h"
#include "esp_sleep.h"

static const char *TAG = "haunted_pumpkin_scarecrow";

// Pin definitions
#define RELAY_TRIGGER_PIN GPIO_NUM_18  // Relay control pin (connects to IN1 on relay module)
#define LED_PIN GPIO_NUM_15            // Built-in yellow LED on Xiao ESP32-C6

// Antenna configuration (ESP32-C6 has internal antenna by default)
// No external antenna pin configuration needed

// Relay configuration
// SainSmart 2-channel 5V relay module:
// - Most relay modules are active LOW (trigger when pin is LOW)
// - Set RELAY_ACTIVE_LOW to 1 for active-low modules (common)
// - Set RELAY_ACTIVE_LOW to 0 for active-high modules (less common)
#define RELAY_ACTIVE_LOW 1

// Trigger duration
#define RELAY_TRIGGER_DURATION_MS 500  // Hold relay closed for 500ms

// Sleep hours (12am to 6am)
#define SLEEP_START_HOUR 0
#define SLEEP_END_HOUR 6

// Zigbee configuration
#define ESP_ZB_PRIMARY_CHANNEL_MASK ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK

// Time synchronization
static bool time_synced = false;
static bool triggered_recently = false;

// Timer handle for non-blocking cooldown
static esp_timer_handle_t cooldown_timer = NULL;

// Task handle for relay trigger
static TaskHandle_t relay_task_handle = NULL;

// Zigbee Time Sync Cluster (using custom manufacturer-specific cluster)
#define ZB_TIME_SYNC_CLUSTER_ID 0xFC00  // Custom cluster for time synchronization
#define ZB_TIME_SYNC_ATTR_ID 0x0000     // Attribute ID for Unix timestamp

void set_system_time(time_t timestamp)
{
    struct timeval tv = { .tv_sec = timestamp, .tv_usec = 0 };
    settimeofday(&tv, NULL);

    // Set timezone to Los Angeles (PST/PDT)
    setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);
    tzset();

    struct tm timeinfo;
    localtime_r(&timestamp, &timeinfo);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);

    ESP_LOGI(TAG, "✓ Time synchronized from coordinator!");
    ESP_LOGI(TAG, "   Unix timestamp: %ld", timestamp);
    ESP_LOGI(TAG, "   Time: %s", time_str);

    time_synced = true;
}

bool is_sleep_time(void)
{
    if (!time_synced) {
        ESP_LOGI(TAG, "Time not synced yet, assuming awake hours");
        return false;
    }

    time_t now = time(NULL);
    struct tm timeinfo;
    localtime_r(&now, &timeinfo);

    ESP_LOGI(TAG, "Current time: %02d:%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);

    // Check if between 12am (0) and 6am
    if (timeinfo.tm_hour >= SLEEP_START_HOUR && timeinfo.tm_hour < SLEEP_END_HOUR) {
        ESP_LOGI(TAG, "Sleep time detected (12am-6am)");
        return true;
    }

    return false;
}

void setup_relay_pin(void)
{
    gpio_config_t relay_conf = {
        .pin_bit_mask = (1ULL << RELAY_TRIGGER_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&relay_conf);

    // Set initial state (relay OFF)
    #if RELAY_ACTIVE_LOW
        gpio_set_level(RELAY_TRIGGER_PIN, 1);  // HIGH = OFF for active-low relay
    #else
        gpio_set_level(RELAY_TRIGGER_PIN, 0);  // LOW = OFF for active-high relay
    #endif

    ESP_LOGI(TAG, "Relay pin initialized on GPIO%d (active-%s)",
             RELAY_TRIGGER_PIN,
             RELAY_ACTIVE_LOW ? "LOW" : "HIGH");
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

// Timer callback to reset cooldown (non-blocking)
static void cooldown_timer_callback(void* arg)
{
    triggered_recently = false;
    ESP_LOGI(TAG, "Cooldown expired, ready for next trigger");
}

// Status task - prints device status every 3 seconds
void status_task(void *pvParameters)
{
    while (1) {
        time_t now;
        struct tm timeinfo;
        char time_str[64];

        time(&now);
        localtime_r(&now, &timeinfo);

        if (time_synced) {
            strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
        } else {
            strcpy(time_str, "NOT SYNCED");
        }

        const char *status = triggered_recently ? "COOLDOWN" : "READY";
        ESP_LOGI(TAG, "Status: %s | Time: %s", status, time_str);

        vTaskDelay(pdMS_TO_TICKS(3000));  // Wait 3 seconds
    }
}

// Task that handles relay triggering (runs in separate task, not Zigbee stack)
void relay_trigger_task(void *pvParameters)
{
    while (1) {
        // Wait for notification from Zigbee handler
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        if (triggered_recently) {
            ESP_LOGI(TAG, "Ignoring trigger - recently activated (cooldown)");
            continue;
        }

        ESP_LOGI(TAG, "🎃 TRIGGERING RELAY (Halloween Decoration)!");

        // Turn on LED to indicate activity
        gpio_set_level(LED_PIN, 1);

        // Activate relay
        #if RELAY_ACTIVE_LOW
            gpio_set_level(RELAY_TRIGGER_PIN, 0);  // LOW = ON for active-low relay
        #else
            gpio_set_level(RELAY_TRIGGER_PIN, 1);  // HIGH = ON for active-high relay
        #endif

        // Hold for duration (OK to block here - we're in our own task)
        vTaskDelay(pdMS_TO_TICKS(RELAY_TRIGGER_DURATION_MS));

        // Deactivate relay
        #if RELAY_ACTIVE_LOW
            gpio_set_level(RELAY_TRIGGER_PIN, 1);  // HIGH = OFF for active-low relay
        #else
            gpio_set_level(RELAY_TRIGGER_PIN, 0);  // LOW = OFF for active-high relay
        #endif

        // Turn off LED
        gpio_set_level(LED_PIN, 0);

        ESP_LOGI(TAG, "Relay trigger complete");

        // Set cooldown to prevent rapid triggering
        triggered_recently = true;

        // Start non-blocking timer to clear cooldown after 2 minutes
        if (cooldown_timer != NULL) {
            esp_timer_stop(cooldown_timer);
            esp_timer_start_once(cooldown_timer, 120000000); // 120 seconds (2 minutes) in microseconds
        }
    }
}

// Called from Zigbee handler - just notifies the relay task (non-blocking)
void trigger_relay(void)
{
    if (relay_task_handle != NULL) {
        xTaskNotifyGive(relay_task_handle);
    }
}

// Zigbee action handler
static esp_err_t zb_action_handler(esp_zb_core_action_callback_id_t callback_id, const void *message)
{
    esp_err_t ret = ESP_OK;

    switch (callback_id) {
        case ESP_ZB_CORE_SET_ATTR_VALUE_CB_ID: {
            const esp_zb_zcl_set_attr_value_message_t *attr_msg = (esp_zb_zcl_set_attr_value_message_t *)message;

            ESP_LOGI(TAG, "Zigbee attribute update - Endpoint: %d, Cluster: 0x%04x, Attr: 0x%04x",
                     attr_msg->info.dst_endpoint,
                     attr_msg->info.cluster,
                     attr_msg->attribute.id);

            // Check for On/Off cluster (0x0006)
            if (attr_msg->info.cluster == ESP_ZB_ZCL_CLUSTER_ID_ON_OFF) {
                if (attr_msg->attribute.id == ESP_ZB_ZCL_ATTR_ON_OFF_ON_OFF_ID) {
                    uint8_t value = *(uint8_t *)attr_msg->attribute.data.value;

                    ESP_LOGI(TAG, "Received On/Off command: %s", value ? "ON" : "OFF");

                    // Trigger on ANY state change (both ON and OFF)
                    // The coordinator sends TOGGLE commands which alternate states
                    trigger_relay();
                }
            }
            // Check for Time Sync cluster (custom cluster 0xFC00)
            else if (attr_msg->info.cluster == ZB_TIME_SYNC_CLUSTER_ID) {
                if (attr_msg->attribute.id == ZB_TIME_SYNC_ATTR_ID) {
                    // Expecting 4-byte Unix timestamp (uint32_t)
                    if (attr_msg->attribute.data.size == 4) {
                        time_t timestamp = *(uint32_t *)attr_msg->attribute.data.value;
                        set_system_time(timestamp);
                    } else {
                        ESP_LOGW(TAG, "Time sync attribute has unexpected size: %d bytes",
                                 attr_msg->attribute.data.size);
                    }
                }
            }
            break;
        }
        case ESP_ZB_CORE_CMD_DEFAULT_RESP_CB_ID:
            ESP_LOGI(TAG, "Zigbee command response received");
            break;
        default:
            ESP_LOGW(TAG, "Receive Zigbee action(0x%x) callback", callback_id);
            break;
    }

    return ret;
}

void esp_zb_app_signal_handler(esp_zb_app_signal_t *signal_struct)
{
    uint32_t *p_sg_p       = signal_struct->p_app_signal;
    esp_err_t err_status = signal_struct->esp_err_status;
    esp_zb_app_signal_type_t sig_type = *p_sg_p;

    switch (sig_type) {
    case ESP_ZB_ZDO_SIGNAL_SKIP_STARTUP:
        ESP_LOGI(TAG, "Zigbee stack initialized");
        esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION);
        break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START:
    case ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT:
        if (err_status == ESP_OK) {
            ESP_LOGI(TAG, "Device started successfully!");
            ESP_LOGI(TAG, "Attempting to join network");
            esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
        } else {
            ESP_LOGE(TAG, "Failed to initialize Zigbee stack (status: %s)", esp_err_to_name(err_status));
        }
        break;
    case ESP_ZB_BDB_SIGNAL_STEERING:
        if (err_status == ESP_OK) {
            esp_zb_ieee_addr_t extended_pan_id;
            esp_zb_get_extended_pan_id(extended_pan_id);
            ESP_LOGI(TAG, "Joined network successfully!");
            ESP_LOGI(TAG, "  Extended PAN ID: %02x:%02x:%02x:%02x:%02x:%02x:%02x:%02x",
                     extended_pan_id[7], extended_pan_id[6], extended_pan_id[5], extended_pan_id[4],
                     extended_pan_id[3], extended_pan_id[2], extended_pan_id[1], extended_pan_id[0]);
            ESP_LOGI(TAG, "  PAN ID: 0x%04hx", esp_zb_get_pan_id());
            ESP_LOGI(TAG, "  Channel: %d", esp_zb_get_current_channel());
        } else {
            ESP_LOGI(TAG, "Network steering failed (status: %s). Retrying...", esp_err_to_name(err_status));
            esp_zb_scheduler_alarm((esp_zb_callback_t)esp_zb_bdb_start_top_level_commissioning, ESP_ZB_BDB_MODE_NETWORK_STEERING, 1000);
        }
        break;
    default:
        ESP_LOGI(TAG, "ZDO signal: %s (0x%x), status: %s", esp_zb_zdo_signal_to_string(sig_type), sig_type,
                 esp_err_to_name(err_status));
        break;
    }
}

static void esp_zb_task(void *pvParameters)
{
    // Initialize Zigbee end device configuration
    esp_zb_cfg_t zb_nwk_cfg;
    zb_nwk_cfg.esp_zb_role = ESP_ZB_DEVICE_TYPE_ED;
    zb_nwk_cfg.install_code_policy = false;
    zb_nwk_cfg.nwk_cfg.zed_cfg.ed_timeout = ESP_ZB_ED_AGING_TIMEOUT_64MIN;
    zb_nwk_cfg.nwk_cfg.zed_cfg.keep_alive = 3000;
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

    // Add custom time sync cluster (0xFC00)
    esp_zb_attribute_list_t *time_sync_cluster = esp_zb_zcl_attr_list_create(ZB_TIME_SYNC_CLUSTER_ID);
    uint32_t time_value = 0;
    esp_zb_custom_cluster_add_custom_attr(time_sync_cluster, ZB_TIME_SYNC_ATTR_ID, ESP_ZB_ZCL_ATTR_TYPE_U32,
                                          ESP_ZB_ZCL_ATTR_ACCESS_READ_WRITE, &time_value);
    esp_zb_cluster_list_add_custom_cluster(cluster_list, time_sync_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Create endpoint
    esp_zb_endpoint_config_t endpoint_config = {
        .endpoint = 1,
        .app_profile_id = ESP_ZB_AF_HA_PROFILE_ID,
        .app_device_id = ESP_ZB_HA_ON_OFF_OUTPUT_DEVICE_ID,
        .app_device_version = 0
    };
    esp_zb_ep_list_add_ep(ep_list, cluster_list, endpoint_config);

    esp_zb_device_register(ep_list);

    // Set action handler
    esp_zb_core_action_handler_register(zb_action_handler);

    ESP_LOGI(TAG, "Starting Zigbee stack");
    ESP_ERROR_CHECK(esp_zb_start(false));
    esp_zb_main_loop_iteration();
}

void enter_deep_sleep(void)
{
    ESP_LOGI(TAG, "Entering deep sleep until 6am...");

    if (!time_synced) {
        ESP_LOGE(TAG, "Time not synced, cannot calculate sleep duration. Sleeping for 6 hours.");
        esp_sleep_enable_timer_wakeup(6 * 60 * 60 * 1000000ULL);
        gpio_set_level(LED_PIN, 0);
        esp_deep_sleep_start();
        return;
    }

    // Calculate sleep duration (until 6am)
    time_t now = time(NULL);
    struct tm timeinfo;
    localtime_r(&now, &timeinfo);

    int hours_until_wakeup = SLEEP_END_HOUR - timeinfo.tm_hour;
    if (hours_until_wakeup <= 0) {
        hours_until_wakeup += 24;
    }

    int total_seconds = (hours_until_wakeup * 3600) - (timeinfo.tm_min * 60) - timeinfo.tm_sec;

    ESP_LOGI(TAG, "Current time: %02d:%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
    ESP_LOGI(TAG, "Sleeping for %d seconds (~%d hours)", total_seconds, hours_until_wakeup);

    // Configure timer wakeup
    esp_sleep_enable_timer_wakeup(total_seconds * 1000000ULL);  // microseconds

    // Turn off LED before sleep
    gpio_set_level(LED_PIN, 0);

    // Enter deep sleep
    esp_deep_sleep_start();
}

void app_main(void)
{
    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  Zigbee Halloween Trigger - Xiao ESP32-C6   ║");
    ESP_LOGI(TAG, "║  Chip: ESP32-C6 (RISC-V)                     ║");
    ESP_LOGI(TAG, "║  Time sync via Zigbee coordinator            ║");
    ESP_LOGI(TAG, "║  Active hours: 6am-12am, Sleep: 12am-6am     ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize hardware
    setup_relay_pin();
    setup_led();

    // Initialize cooldown timer (non-blocking)
    const esp_timer_create_args_t cooldown_timer_args = {
        .callback = &cooldown_timer_callback,
        .name = "cooldown"
    };
    ESP_ERROR_CHECK(esp_timer_create(&cooldown_timer_args, &cooldown_timer));
    ESP_LOGI(TAG, "Cooldown timer initialized");

    // Create relay trigger task (separate from Zigbee stack)
    xTaskCreate(relay_trigger_task, "relay_trigger", 2048, NULL, 5, &relay_task_handle);
    ESP_LOGI(TAG, "Relay trigger task created");

    // Create status task (prints status every 3 seconds)
    xTaskCreate(status_task, "status", 2048, NULL, 3, NULL);
    ESP_LOGI(TAG, "Status task created");

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
