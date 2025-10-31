#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "esp_mac.h"
#include "driver/gpio.h"
#include "nvs_flash.h"
#include "esp_zigbee_core.h"
#include "esp_sleep.h"
#include "led_strip.h"

static const char *TAG = "rip_tombstone";

// Pin definitions
#define PIR_PIN GPIO_NUM_18
#define LED_PIN GPIO_NUM_15           // Built-in yellow LED on Xiao ESP32-C6
#define NEOPIXEL_PIN GPIO_NUM_19      // NeoPixel strip data pin
#define NEOPIXEL_COUNT 10             // 10 LEDs in the strip

// Sleep hours (12am to 6am)
#define SLEEP_START_HOUR 0
#define SLEEP_END_HOUR 6

// Zigbee configuration - scan all channels to find coordinator
#define ESP_ZB_PRIMARY_CHANNEL_MASK ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK

// Time synchronization
static bool time_synced = false;
static bool triggered_recently = false;

// Timer handle for non-blocking cooldown
static esp_timer_handle_t cooldown_timer = NULL;

// LED strip handle
static led_strip_handle_t neopixel_strip;

// Task handles
static TaskHandle_t motion_task_handle = NULL;

// Zigbee Time Sync Cluster (using custom manufacturer-specific cluster)
#define ZB_TIME_SYNC_CLUSTER_ID 0xFC00  // Custom cluster for time synchronization
#define ZB_TIME_SYNC_ATTR_ID 0x0000     // Attribute ID for Unix timestamp

// Custom Trigger Request Cluster - to ask coordinator to trigger scarecrow
#define ZB_TRIGGER_REQUEST_CLUSTER_ID 0xFC01  // Custom cluster for trigger requests
#define ZB_TRIGGER_REQUEST_ATTR_ID 0x0000     // Attribute for trigger target (1=scarecrow)

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

    ESP_LOGI(TAG, "Time synchronized from coordinator!");
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

void setup_pir(void)
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

void setup_neopixels(void)
{
    led_strip_config_t strip_config = {
        .strip_gpio_num = NEOPIXEL_PIN,
        .max_leds = NEOPIXEL_COUNT,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,
        .led_model = LED_MODEL_WS2812,
        .flags.invert_out = false,
    };

    led_strip_rmt_config_t rmt_config = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = 10 * 1000 * 1000,
        .flags.with_dma = false,
    };

    ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &neopixel_strip));
    led_strip_clear(neopixel_strip);

    ESP_LOGI(TAG, "NeoPixel strip initialized on GPIO%d (%d LEDs)", NEOPIXEL_PIN, NEOPIXEL_COUNT);
}

void blink_neopixels_red(void)
{
    ESP_LOGI(TAG, "Blinking NeoPixels red 20 times!");

    for (int blink = 0; blink < 20; blink++) {
        for (int i = 0; i < NEOPIXEL_COUNT; i++) {
            led_strip_set_pixel(neopixel_strip, i, 255, 0, 0);
        }
        led_strip_refresh(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(150));

        led_strip_clear(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(150));
    }

    ESP_LOGI(TAG, "Blink complete");
}

void blink_neopixels_rainbow(void)
{
    ESP_LOGI(TAG, "RAINBOW SHOW! Blinking NeoPixels random rainbow 50 times!");

    for (int blink = 0; blink < 50; blink++) {
        for (int i = 0; i < NEOPIXEL_COUNT; i++) {
            int color = esp_random() % 6;
            uint8_t r = 0, g = 0, b = 0;

            switch(color) {
                case 0: r = 255; g = 0;   b = 0;   break;
                case 1: r = 255; g = 127; b = 0;   break;
                case 2: r = 255; g = 255; b = 0;   break;
                case 3: r = 0;   g = 255; b = 0;   break;
                case 4: r = 0;   g = 0;   b = 255; break;
                case 5: r = 128; g = 0;   b = 255; break;
            }

            led_strip_set_pixel(neopixel_strip, i, g, r, b);
        }
        led_strip_refresh(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(75));

        led_strip_clear(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(75));
    }

    ESP_LOGI(TAG, "Rainbow show complete!");
}

// Timer callback to reset cooldown
static void cooldown_timer_callback(void* arg)
{
    triggered_recently = false;
    ESP_LOGI(TAG, "Cooldown expired, ready for next trigger");
}

// Trigger the haunted scarecrow via coordinator
void trigger_haunted_scarecrow(void)
{
    ESP_LOGI(TAG, "Sending trigger request to coordinator for scarecrow...");

    // Send trigger request to coordinator using custom cluster
    // We write to the trigger request attribute on the coordinator
    esp_zb_zcl_write_attr_cmd_t write_req;

    uint8_t trigger_target = 1; // 1 = trigger scarecrow

    esp_zb_zcl_attribute_t attr_list[] = {
        {
            .id = ZB_TRIGGER_REQUEST_ATTR_ID,
            .data.type = ESP_ZB_ZCL_ATTR_TYPE_U8,
            .data.value = &trigger_target,
            .data.size = sizeof(trigger_target),
        }
    };

    write_req.address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
    write_req.zcl_basic_cmd.dst_addr_u.addr_short = 0x0000; // Coordinator address is always 0x0000
    write_req.zcl_basic_cmd.dst_endpoint = 1;
    write_req.zcl_basic_cmd.src_endpoint = 1;
    write_req.clusterID = ZB_TRIGGER_REQUEST_CLUSTER_ID;
    write_req.attr_number = 1;
    write_req.attr_field = attr_list;

    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_write_attr_cmd_req(&write_req);
    esp_zb_lock_release();

    ESP_LOGI(TAG, "Trigger request sent to coordinator");
}

// Status task - prints device status every 10 seconds
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
        ESP_LOGI(TAG, "Status: %s | Time: %s",
                 status, time_str);

        vTaskDelay(pdMS_TO_TICKS(10000));
    }
}

// Motion detection task
void motion_detection_task(void *pvParameters)
{
    ESP_LOGI(TAG, "Warming up PIR sensor (30 seconds)...");
    vTaskDelay(pdMS_TO_TICKS(30000));
    ESP_LOGI(TAG, "PIR sensor ready!");

    bool last_motion = false;
    int motion_count = 0;
    int64_t first_motion_time = 0;
    int64_t last_motion_time = 0;

    while (1) {
        bool motion_detected = gpio_get_level(PIR_PIN);
        int64_t current_time = esp_timer_get_time() / 1000000;

        // Reset counter if 30 seconds passed since last motion
        if (motion_count > 0 && last_motion_time > 0) {
            if ((current_time - last_motion_time) > 30) {
                ESP_LOGI(TAG, "No motion for 30s - Resetting counter (was %d/3)", motion_count);
                motion_count = 0;
                first_motion_time = 0;
                last_motion_time = 0;
            }
        }

        if (motion_detected) {
            gpio_set_level(LED_PIN, 1);

            if (!last_motion && !triggered_recently) {
                if (motion_count == 0) {
                    first_motion_time = current_time;
                    motion_count = 1;
                    last_motion_time = current_time;
                    ESP_LOGI(TAG, "MOTION DETECTED! Count: 1/3");
                } else {
                    // Check if within 90 second window
                    if ((current_time - first_motion_time) <= 90) {
                        motion_count++;
                        last_motion_time = current_time;
                        ESP_LOGI(TAG, "MOTION DETECTED! Count: %d/3", motion_count);
                    } else {
                        ESP_LOGI(TAG, "Timer reset (>90s). Starting new count.");
                        first_motion_time = current_time;
                        motion_count = 1;
                        last_motion_time = current_time;
                        ESP_LOGI(TAG, "MOTION DETECTED! Count: 1/3");
                    }
                }

                triggered_recently = true;

                // Trigger appropriate light show
                if (motion_count >= 3) {
                    ESP_LOGI(TAG, "THREE MOTIONS IN 90 SECONDS! RAINBOW SHOW TIME!");
                    blink_neopixels_rainbow();
                    motion_count = 0;
                    first_motion_time = 0;
                    last_motion_time = 0;
                } else {
                    blink_neopixels_red();
                }

                // Always try to trigger the haunted scarecrow on ANY motion
                trigger_haunted_scarecrow();

                // Start cooldown timer (2 minutes)
                if (cooldown_timer != NULL) {
                    esp_timer_stop(cooldown_timer);
                    esp_timer_start_once(cooldown_timer, 120000000); // 2 minutes
                }
            }
        } else {
            gpio_set_level(LED_PIN, 0);

            if (last_motion) {
                ESP_LOGI(TAG, "No motion");
            }
        }

        last_motion = motion_detected;
        vTaskDelay(pdMS_TO_TICKS(100));
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

            // Check for On/Off cluster (0x0006) - trigger NeoPixel animation
            if (attr_msg->info.cluster == ESP_ZB_ZCL_CLUSTER_ID_ON_OFF) {
                if (attr_msg->attribute.id == ESP_ZB_ZCL_ATTR_ON_OFF_ON_OFF_ID) {
                    bool on_off = *(bool *)attr_msg->attribute.data.value;
                    ESP_LOGI(TAG, "Received On/Off command: %s", on_off ? "ON" : "OFF");

                    if (on_off) {
                        // Trigger NeoPixel flash animation
                        ESP_LOGI(TAG, "Triggering NeoPixel flash from coordinator");
                        blink_neopixels_red();
                    }
                }
            }
            // Check for Time Sync cluster (custom cluster 0xFC00)
            else if (attr_msg->info.cluster == ZB_TIME_SYNC_CLUSTER_ID) {
                if (attr_msg->attribute.id == ZB_TIME_SYNC_ATTR_ID) {
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

    // Add on/off cluster (server role - to be controlled by coordinator)
    esp_zb_on_off_cluster_cfg_t on_off_cfg = {
        .on_off = ESP_ZB_ZCL_ON_OFF_ON_OFF_DEFAULT_VALUE,
    };
    esp_zb_attribute_list_t *on_off_cluster = esp_zb_on_off_cluster_create(&on_off_cfg);
    esp_zb_cluster_list_add_on_off_cluster(cluster_list, on_off_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Add on/off cluster client role to send commands to scarecrow
    esp_zb_attribute_list_t *on_off_cluster_client = esp_zb_on_off_cluster_create(NULL);
    esp_zb_cluster_list_add_on_off_cluster(cluster_list, on_off_cluster_client, ESP_ZB_ZCL_CLUSTER_CLIENT_ROLE);

    // Add custom time sync cluster (0xFC00) - SERVER role to receive time from coordinator
    esp_zb_attribute_list_t *time_sync_cluster = esp_zb_zcl_attr_list_create(ZB_TIME_SYNC_CLUSTER_ID);
    uint32_t time_value = 0;
    esp_zb_custom_cluster_add_custom_attr(time_sync_cluster, ZB_TIME_SYNC_ATTR_ID, ESP_ZB_ZCL_ATTR_TYPE_U32,
                                          ESP_ZB_ZCL_ATTR_ACCESS_READ_WRITE, &time_value);
    esp_zb_cluster_list_add_custom_cluster(cluster_list, time_sync_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

    // Add trigger request cluster (0xFC01) - CLIENT role to send trigger requests to coordinator
    esp_zb_attribute_list_t *trigger_request_cluster = esp_zb_zcl_attr_list_create(ZB_TRIGGER_REQUEST_CLUSTER_ID);
    esp_zb_cluster_list_add_custom_cluster(cluster_list, trigger_request_cluster, ESP_ZB_ZCL_CLUSTER_CLIENT_ROLE);

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

    // Get and print IEEE address for coordinator configuration
    esp_zb_ieee_addr_t ieee_addr;
    esp_read_mac(ieee_addr, ESP_MAC_IEEE802154);
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "Device IEEE Address: %02x:%02x:%02x:%02x:%02x:%02x:%02x:%02x",
             ieee_addr[7], ieee_addr[6], ieee_addr[5], ieee_addr[4],
             ieee_addr[3], ieee_addr[2], ieee_addr[1], ieee_addr[0]);
    ESP_LOGI(TAG, "Add this address to the coordinator's allow list!");
    ESP_LOGI(TAG, "========================================");

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

    esp_sleep_enable_timer_wakeup(total_seconds * 1000000ULL);
    gpio_set_level(LED_PIN, 0);
    led_strip_clear(neopixel_strip);

    esp_deep_sleep_start();
}

void app_main(void)
{
    ESP_LOGI(TAG, "+----------------------------------------------+");
    ESP_LOGI(TAG, "|  Zigbee RIP Tombstone - Xiao ESP32-C6       |");
    ESP_LOGI(TAG, "|  Chip: ESP32-C6 (RISC-V)                    |");
    ESP_LOGI(TAG, "|  PIR Motion + NeoPixels + Zigbee Trigger    |");
    ESP_LOGI(TAG, "|  Time sync via Zigbee coordinator           |");
    ESP_LOGI(TAG, "|  Active hours: 6am-12am, Sleep: 12am-6am    |");
    ESP_LOGI(TAG, "+----------------------------------------------+");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize hardware
    setup_pir();
    setup_led();
    setup_neopixels();

    // Initialize cooldown timer
    const esp_timer_create_args_t cooldown_timer_args = {
        .callback = &cooldown_timer_callback,
        .name = "cooldown"
    };
    ESP_ERROR_CHECK(esp_timer_create(&cooldown_timer_args, &cooldown_timer));
    ESP_LOGI(TAG, "Cooldown timer initialized");

    // Create status task
    xTaskCreate(status_task, "status", 2048, NULL, 3, NULL);
    ESP_LOGI(TAG, "Status task created");

    // Create motion detection task
    xTaskCreate(motion_detection_task, "motion", 4096, NULL, 5, &motion_task_handle);
    ESP_LOGI(TAG, "Motion detection task created");

    // Check if it's sleep time
    if (is_sleep_time()) {
        enter_deep_sleep();
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
