#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_zigbee_core.h"

static const char *TAG = "xiao_zigbee";

// UART pins for communication with TinyS3
#define UART_TX_PIN GPIO_NUM_16  // TX to TinyS3 (D6)
#define UART_RX_PIN GPIO_NUM_17  // RX from TinyS3 (D7)
#define UART_NUM UART_NUM_1
#define UART_BUF_SIZE (1024)

// UART command protocol (must match TinyS3)
#define CMD_TRIGGER_RIP 0x01
#define CMD_TRIGGER_HALLOWEEN 0x02
#define CMD_TRIGGER_BOTH 0x03
#define CMD_STATUS_REQUEST 0x10
#define CMD_STATUS_RESPONSE 0x11
#define CMD_TIME_SYNC 0x20

// Zigbee configuration
#define ZIGBEE_CHANNEL 15
#define ESP_ZB_PRIMARY_CHANNEL_MASK (1 << ZIGBEE_CHANNEL)

// Device tracking (IEEE addresses of bound devices)
typedef struct {
    uint64_t ieee_addr;
    uint8_t endpoint;
    char name[32];
    bool is_bound;
} zigbee_device_t;

static zigbee_device_t rip_tombstone = {0};
static zigbee_device_t halloween_trigger = {0};

// ============================================================================
// UART Communication with TinyS3
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

    ESP_LOGI(TAG, "UART initialized (TX:%d, RX:%d) for TinyS3 communication", UART_TX_PIN, UART_RX_PIN);
}

// ============================================================================
// Zigbee Coordinator Functions
// ============================================================================

void zigbee_send_on_command(uint64_t ieee_addr, uint8_t endpoint)
{
    ESP_LOGI(TAG, "Sending Zigbee ON command to device 0x%llx endpoint %d",
             ieee_addr, endpoint);

    esp_zb_zcl_on_off_cmd_t cmd_req;
    cmd_req.zcl_basic_cmd.dst_addr_u.addr_short = 0xFFFF; // Broadcast
    cmd_req.zcl_basic_cmd.dst_endpoint = endpoint;
    cmd_req.zcl_basic_cmd.src_endpoint = 1;
    cmd_req.address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
    cmd_req.on_off_cmd_id = ESP_ZB_ZCL_CMD_ON_OFF_ON_ID;

    esp_zb_zcl_on_off_cmd_req(&cmd_req);
}

void trigger_rip_tombstone(void)
{
    if (rip_tombstone.is_bound) {
        ESP_LOGI(TAG, "🎃 Triggering RIP Tombstone");
        zigbee_send_on_command(rip_tombstone.ieee_addr, rip_tombstone.endpoint);
    } else {
        ESP_LOGW(TAG, "RIP Tombstone not bound");
    }
}

void trigger_halloween_decoration(void)
{
    if (halloween_trigger.is_bound) {
        ESP_LOGI(TAG, "🎃 Triggering Halloween Decoration");
        zigbee_send_on_command(halloween_trigger.ieee_addr, halloween_trigger.endpoint);
    } else {
        ESP_LOGW(TAG, "Halloween Trigger not bound");
    }
}

static esp_err_t zb_action_handler(esp_zb_core_action_callback_id_t callback_id, const void *message)
{
    esp_err_t ret = ESP_OK;

    switch (callback_id) {
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
            ESP_LOGI(TAG, "Zigbee coordinator started successfully!");
            ESP_LOGI(TAG, "Start network formation");
            esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_FORMATION);
        } else {
            ESP_LOGE(TAG, "Failed to initialize Zigbee stack (status: %s)", esp_err_to_name(err_status));
        }
        break;
    case ESP_ZB_BDB_SIGNAL_FORMATION:
        if (err_status == ESP_OK) {
            esp_zb_ieee_addr_t extended_pan_id;
            esp_zb_get_extended_pan_id(extended_pan_id);
            ESP_LOGI(TAG, "Formed network successfully (Extended PAN ID: %02x:%02x:%02x:%02x:%02x:%02x:%02x:%02x, PAN ID: 0x%04hx, Channel:%d)",
                     extended_pan_id[7], extended_pan_id[6], extended_pan_id[5], extended_pan_id[4],
                     extended_pan_id[3], extended_pan_id[2], extended_pan_id[1], extended_pan_id[0],
                     esp_zb_get_pan_id(), esp_zb_get_current_channel());
            esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
        } else {
            ESP_LOGI(TAG, "Restart network formation (status: %s)", esp_err_to_name(err_status));
            esp_zb_scheduler_alarm((esp_zb_callback_t)esp_zb_bdb_start_top_level_commissioning, ESP_ZB_BDB_MODE_NETWORK_FORMATION, 1000);
        }
        break;
    case ESP_ZB_BDB_SIGNAL_STEERING:
        if (err_status == ESP_OK) {
            ESP_LOGI(TAG, "Network steering started - devices can now join");
        }
        break;
    case ESP_ZB_ZDO_SIGNAL_DEVICE_ANNCE:
        {
            esp_zb_zdo_signal_device_annce_params_t *dev_annce_params = (esp_zb_zdo_signal_device_annce_params_t *)esp_zb_app_signal_get_params(p_sg_p);
            ESP_LOGI(TAG, "New device joined: short=0x%04hx", dev_annce_params->device_short_addr);
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
    // Configure as coordinator
    esp_zb_cfg_t zb_nwk_cfg;
    zb_nwk_cfg.esp_zb_role = ESP_ZB_DEVICE_TYPE_COORDINATOR;
    zb_nwk_cfg.install_code_policy = false;
    zb_nwk_cfg.nwk_cfg.zczr_cfg.max_children = 10;

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

    // Add on/off cluster (client role for coordinator)
    esp_zb_on_off_cluster_cfg_t on_off_cfg = {
        .on_off = ESP_ZB_ZCL_ON_OFF_ON_OFF_DEFAULT_VALUE,
    };
    esp_zb_attribute_list_t *on_off_cluster = esp_zb_on_off_cluster_create(&on_off_cfg);
    esp_zb_cluster_list_add_on_off_cluster(cluster_list, on_off_cluster, ESP_ZB_ZCL_CLUSTER_CLIENT_ROLE);

    // Create endpoint
    esp_zb_endpoint_config_t endpoint_config = {
        .endpoint = 1,
        .app_profile_id = ESP_ZB_AF_HA_PROFILE_ID,
        .app_device_id = ESP_ZB_HA_ON_OFF_SWITCH_DEVICE_ID,
        .app_device_version = 0
    };
    esp_zb_ep_list_add_ep(ep_list, cluster_list, endpoint_config);

    esp_zb_device_register(ep_list);

    // Set action handler
    esp_zb_core_action_handler_register(zb_action_handler);

    ESP_LOGI(TAG, "Starting Zigbee coordinator on channel %d", ZIGBEE_CHANNEL);
    ESP_ERROR_CHECK(esp_zb_start(false));
    esp_zb_main_loop_iteration();
}

// ============================================================================
// UART Command Handler Task
// ============================================================================

void uart_handler_task(void *pvParameters)
{
    uint8_t data[16];

    ESP_LOGI(TAG, "UART handler task started");

    while (1) {
        int len = uart_read_bytes(UART_NUM, data, sizeof(data), pdMS_TO_TICKS(100));

        if (len > 0) {
            // Look for command frame: 0xAA <cmd> [data...] 0x55
            for (int i = 0; i < len - 2; i++) {
                if (data[i] == 0xAA) {
                    uint8_t cmd = data[i + 1];

                    switch (cmd) {
                        case CMD_TRIGGER_RIP:
                            ESP_LOGI(TAG, "UART received: CMD_TRIGGER_RIP");
                            trigger_rip_tombstone();
                            break;

                        case CMD_TRIGGER_HALLOWEEN:
                            ESP_LOGI(TAG, "UART received: CMD_TRIGGER_HALLOWEEN");
                            trigger_halloween_decoration();
                            break;

                        case CMD_TRIGGER_BOTH:
                            ESP_LOGI(TAG, "UART received: CMD_TRIGGER_BOTH");
                            trigger_rip_tombstone();
                            vTaskDelay(pdMS_TO_TICKS(100));
                            trigger_halloween_decoration();
                            break;

                        case CMD_TIME_SYNC:
                            // Time sync frame: 0xAA 0x20 timestamp(4 bytes) 0x55
                            if (i + 6 < len && data[i + 6] == 0x55) {
                                time_t timestamp = ((uint32_t)data[i + 2] << 24) |
                                                 ((uint32_t)data[i + 3] << 16) |
                                                 ((uint32_t)data[i + 4] << 8) |
                                                 ((uint32_t)data[i + 5]);

                                struct timeval tv = { .tv_sec = timestamp, .tv_usec = 0 };
                                settimeofday(&tv, NULL);

                                // Set timezone to Los Angeles
                                setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);
                                tzset();

                                struct tm timeinfo;
                                localtime_r(&timestamp, &timeinfo);
                                char time_str[64];
                                strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);

                                ESP_LOGI(TAG, "✓ Time synchronized from TinyS3!");
                                ESP_LOGI(TAG, "   Unix timestamp: %ld", timestamp);
                                ESP_LOGI(TAG, "   Time: %s", time_str);
                            }
                            break;

                        default:
                            ESP_LOGW(TAG, "UART received unknown command: 0x%02x", cmd);
                            break;
                    }
                }
            }
        }
    }
}

// ============================================================================
// Main Application
// ============================================================================

void app_main(void)
{
    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  XIAO ESP32-C6 Zigbee Coordinator            ║");
    ESP_LOGI(TAG, "║  Controlled via UART from TinyS3             ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize UART for TinyS3 communication
    setup_uart();

    // Initialize device records
    strcpy(rip_tombstone.name, "RIP Tombstone");
    rip_tombstone.endpoint = 1;
    rip_tombstone.is_bound = true;

    strcpy(halloween_trigger.name, "Halloween Trigger");
    halloween_trigger.endpoint = 1;
    halloween_trigger.is_bound = true;

    // Start UART handler task
    xTaskCreate(uart_handler_task, "UART_handler", 2048, NULL, 10, NULL);

    // Start Zigbee coordinator
    ESP_LOGI(TAG, "Starting Zigbee coordinator...");
    ESP_LOGI(TAG, "   Channel: %d (2.4GHz @ ~%d MHz)", ZIGBEE_CHANNEL, 2405 + 5 * ZIGBEE_CHANNEL);
    xTaskCreate(esp_zb_task, "Zigbee_main", 4096, NULL, 5, NULL);

    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  System Ready!                               ║");
    ESP_LOGI(TAG, "║  - Zigbee coordinator active                 ║");
    ESP_LOGI(TAG, "║  - UART receiver listening for commands      ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Main loop - just keep alive
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));

        time_t now = time(NULL);
        struct tm timeinfo;
        localtime_r(&now, &timeinfo);
        char time_str[64];
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
        ESP_LOGI(TAG, "Time: %s", time_str);
    }
}
