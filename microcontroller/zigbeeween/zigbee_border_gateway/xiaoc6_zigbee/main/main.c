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
#include "nwk/esp_zigbee_nwk.h"

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
#define CMD_DEVICE_JOINED 0x30
#define CMD_DEVICE_LEFT 0x31

// Device IDs for join/leave notifications
#define DEVICE_ID_RIP 1
#define DEVICE_ID_HALLOWEEN 2

// Hardcoded IEEE addresses to identify specific devices
#define HALLOWEEN_TRIGGER_IEEE 0x9888e0fffe7ade0cULL
#define RIP_TOMBSTONE_IEEE     0x9888e0fffe7f971cULL  // RIP Tombstone device

// Zigbee configuration
#define ZIGBEE_CHANNEL 15
#define ESP_ZB_PRIMARY_CHANNEL_MASK (1 << ZIGBEE_CHANNEL)

// Zigbee Time Sync Cluster (must match end devices)
#define ZB_TIME_SYNC_CLUSTER_ID 0xFC00
#define ZB_TIME_SYNC_ATTR_ID 0x0000

// Trigger Request Cluster - for end devices to request coordinator to trigger other devices
#define ZB_TRIGGER_REQUEST_CLUSTER_ID 0xFC01
#define ZB_TRIGGER_REQUEST_ATTR_ID 0x0000

// Device tracking (IEEE addresses of bound devices)
typedef struct {
    uint64_t ieee_addr;
    uint16_t short_addr;
    uint8_t endpoint;
    char name[32];
    bool is_bound;
    bool time_synced;
    time_t last_time_sync;
    time_t last_trigger;  // Track when device was last triggered
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

void uart_send_device_status(void)
{
    // Frame format: 0xAA CMD_STATUS_RESPONSE flags(2 bytes) 0x55
    // Flags bit 0: RIP tombstone time synced
    // Flags bit 1: Haunted pumpkin scarecrow time synced
    // Flags bit 2: RIP tombstone connected
    // Flags bit 3: Haunted pumpkin scarecrow connected
    // Flags bit 4: RIP tombstone in cooldown
    // Flags bit 5: Haunted pumpkin scarecrow in cooldown
    uint16_t flags = 0;

    if (rip_tombstone.time_synced) flags |= (1 << 0);
    if (halloween_trigger.time_synced) flags |= (1 << 1);
    if (rip_tombstone.is_bound) flags |= (1 << 2);
    if (halloween_trigger.is_bound) flags |= (1 << 3);

    // Check cooldown status (2 minutes = 120 seconds)
    time_t now = time(NULL);
    if (rip_tombstone.last_trigger > 0 && (now - rip_tombstone.last_trigger) < 120) {
        flags |= (1 << 4);
    }
    if (halloween_trigger.last_trigger > 0 && (now - halloween_trigger.last_trigger) < 120) {
        flags |= (1 << 5);
    }

    uint8_t data[5];
    data[0] = 0xAA;  // Start byte
    data[1] = CMD_STATUS_RESPONSE;
    data[2] = (flags >> 8) & 0xFF;  // High byte
    data[3] = flags & 0xFF;          // Low byte
    data[4] = 0x55;  // End byte

    uart_write_bytes(UART_NUM, data, sizeof(data));
    ESP_LOGI(TAG, "UART sent device status: flags=0x%04x", flags);
}

void uart_send_device_event(uint8_t cmd, uint8_t device_id)
{
    // Frame format: 0xAA CMD device_id 0x55
    uint8_t data[4];
    data[0] = 0xAA;
    data[1] = cmd;
    data[2] = device_id;
    data[3] = 0x55;

    uart_write_bytes(UART_NUM, data, sizeof(data));

    const char *event_name = (cmd == CMD_DEVICE_JOINED) ? "joined" : "left";
    const char *device_name = (device_id == DEVICE_ID_RIP) ? "RIP Tombstone" : "Haunted Pumpkin Scarecrow";
    ESP_LOGI(TAG, "UART sent: Device %s - %s", event_name, device_name);
}

// ============================================================================
// Forward declarations
// ============================================================================

void zigbee_send_time_sync_to_device(uint16_t short_addr, uint8_t endpoint, const char* device_name);

// ============================================================================
// Neighbor Table and Signal Strength Monitoring
// ============================================================================

void check_device_signal_strength(void)
{
    esp_zb_nwk_info_iterator_t iterator = ESP_ZB_NWK_INFO_ITERATOR_INIT;
    esp_zb_nwk_neighbor_info_t nbr_info;
    bool found_any = false;
    int total_devices = 0;

    while (esp_zb_nwk_get_next_neighbor(&iterator, &nbr_info) == ESP_OK) {
        total_devices++;

        // Get IEEE address from neighbor info
        uint64_t ieee_addr = 0;
        memcpy(&ieee_addr, nbr_info.ieee_addr, sizeof(esp_zb_ieee_addr_t));

        // Check if this is a known device by IEEE address FIRST
        // (before filtering by signal quality)
        bool is_known_device = (ieee_addr == HALLOWEEN_TRIGGER_IEEE) ||
                               (ieee_addr == RIP_TOMBSTONE_IEEE && RIP_TOMBSTONE_IEEE != 0);

        // Debug: Log ALL devices in neighbor table
        ESP_LOGI(TAG, "Neighbor table entry %d: short=0x%04x, ieee=0x%016llx, LQI=%d, RSSI=%d %s",
                 total_devices, nbr_info.short_addr, ieee_addr, nbr_info.lqi, nbr_info.rssi,
                 is_known_device ? "[KNOWN]" : "");

        // Skip devices with invalid signal values ONLY if they're unknown
        if (!is_known_device && (nbr_info.lqi == 0 || nbr_info.rssi > 0)) {
            ESP_LOGW(TAG, "  ^ Skipping unknown device (invalid signal values)");
            continue;
        }

        // For known devices with invalid signals, we'll register them but won't log signal strength
        bool has_valid_signals = !(nbr_info.lqi == 0 || nbr_info.rssi > 0);
        found_any = true;

        // Match neighbor with our tracked devices by IEEE address
        const char *device_name = NULL;
        bool is_synced = false;
        bool is_known = false;

        if (ieee_addr == HALLOWEEN_TRIGGER_IEEE) {
            device_name = "Pumpkin Scarecrow";
            is_known = true;

            // Auto-register if not already registered
            if (halloween_trigger.short_addr == 0 || !halloween_trigger.is_bound) {
                halloween_trigger.short_addr = nbr_info.short_addr;
                halloween_trigger.ieee_addr = ieee_addr;
                halloween_trigger.endpoint = 1;
                halloween_trigger.is_bound = true;

                ESP_LOGI(TAG, "Auto-registered Haunted Pumpkin Scarecrow (0x%04x, ieee=0x%016llx)",
                         nbr_info.short_addr, ieee_addr);

                // Send time sync to newly registered device
                zigbee_send_time_sync_to_device(nbr_info.short_addr, 1, "Haunted Pumpkin Scarecrow");
                halloween_trigger.time_synced = true;
                halloween_trigger.last_time_sync = time(NULL);

                // Notify TinyS3
                uart_send_device_event(CMD_DEVICE_JOINED, DEVICE_ID_HALLOWEEN);
            }

            is_synced = halloween_trigger.time_synced;
        } else if (ieee_addr == RIP_TOMBSTONE_IEEE && RIP_TOMBSTONE_IEEE != 0) {
            device_name = "RIP";
            is_known = true;

            // Auto-register if not already registered
            if (rip_tombstone.short_addr == 0 || !rip_tombstone.is_bound) {
                rip_tombstone.short_addr = nbr_info.short_addr;
                rip_tombstone.ieee_addr = ieee_addr;
                rip_tombstone.endpoint = 1;
                rip_tombstone.is_bound = true;

                ESP_LOGI(TAG, "Auto-registered RIP Tombstone (0x%04x, ieee=0x%016llx)",
                         nbr_info.short_addr, ieee_addr);

                // Send time sync to newly registered device
                zigbee_send_time_sync_to_device(nbr_info.short_addr, 1, "RIP Tombstone");
                rip_tombstone.time_synced = true;
                rip_tombstone.last_time_sync = time(NULL);

                // Notify TinyS3
                uart_send_device_event(CMD_DEVICE_JOINED, DEVICE_ID_RIP);
            }

            is_synced = rip_tombstone.time_synced;
        } else {
            // Unknown device - log it so user can add to hardcoded list
            ESP_LOGW(TAG, "Unknown device (0x%04x, ieee=0x%016llx): LQI %3d | RSSI %4d dBm",
                     nbr_info.short_addr, ieee_addr, nbr_info.lqi, nbr_info.rssi);
            continue;  // Skip logging in main output
        }

        // Only log known devices with valid signal values
        if (is_known && has_valid_signals) {
            // LQI: 0-255 (higher is better, >200 is excellent, 100-200 is good, <100 is poor)
            // RSSI: dBm (closer to 0 is better, -40 is excellent, -70 is good, -90 is poor)
            ESP_LOGI(TAG, "%s (0x%04x): LQI %3d/255 | RSSI %4d dBm | Sync %s",
                     device_name, nbr_info.short_addr, nbr_info.lqi, nbr_info.rssi, is_synced ? "Y" : "N");
        } else if (is_known && !has_valid_signals) {
            ESP_LOGI(TAG, "%s (0x%04x): Registered (waiting for signal data) | Sync %s",
                     device_name, nbr_info.short_addr, is_synced ? "Y" : "N");
        }
    }

    if (total_devices == 0) {
        ESP_LOGI(TAG, "No devices in neighbor table");
    } else if (!found_any) {
        ESP_LOGI(TAG, "Found %d device(s) in neighbor table, but none with valid signal values", total_devices);
    }
}

void signal_strength_task(void *pvParameters)
{
    // Wait 5 seconds before first check (let devices join)
    vTaskDelay(pdMS_TO_TICKS(5000));

    while (1) {
        check_device_signal_strength();
        vTaskDelay(pdMS_TO_TICKS(3000)); // Check every 3 seconds
    }
}

// ============================================================================
// Zigbee Coordinator Functions
// ============================================================================

void zigbee_send_on_command(uint16_t short_addr, uint8_t endpoint)
{
    if (short_addr == 0) {
        ESP_LOGW(TAG, "Cannot send command - device not registered (short address is 0)");
        return;
    }

    ESP_LOGI(TAG, "Sending Zigbee TOGGLE command to device 0x%04hx endpoint %d", short_addr, endpoint);

    esp_zb_zcl_on_off_cmd_t cmd_req;
    cmd_req.zcl_basic_cmd.dst_addr_u.addr_short = short_addr; // Unicast to specific device
    cmd_req.zcl_basic_cmd.dst_endpoint = endpoint;
    cmd_req.zcl_basic_cmd.src_endpoint = 1;
    cmd_req.address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
    cmd_req.on_off_cmd_id = ESP_ZB_ZCL_CMD_ON_OFF_TOGGLE_ID; // Use TOGGLE instead of ON

    esp_zb_zcl_on_off_cmd_req(&cmd_req);
}

void zigbee_send_time_sync_to_device(uint16_t short_addr, uint8_t endpoint, const char* device_name)
{
    if (short_addr == 0) {
        ESP_LOGW(TAG, "Cannot send time sync to %s - device not registered", device_name);
        return;
    }

    time_t now = time(NULL);
    if (now < 1000000000) {
        ESP_LOGW(TAG, "System time not set, skipping time sync to %s", device_name);
        return;
    }

    uint32_t timestamp = (uint32_t)now;

    ESP_LOGI(TAG, "Sending time sync to %s (0x%04hx): timestamp=%lu", device_name, short_addr, timestamp);

    // Create attribute write command for custom time sync cluster
    esp_zb_zcl_write_attr_cmd_t write_req;
    esp_zb_zcl_attribute_t attr;

    attr.id = ZB_TIME_SYNC_ATTR_ID;
    attr.data.type = ESP_ZB_ZCL_ATTR_TYPE_U32;
    attr.data.value = &timestamp;
    attr.data.size = sizeof(uint32_t);

    write_req.address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
    write_req.zcl_basic_cmd.dst_addr_u.addr_short = short_addr;
    write_req.zcl_basic_cmd.dst_endpoint = endpoint;
    write_req.zcl_basic_cmd.src_endpoint = 1;
    write_req.clusterID = ZB_TIME_SYNC_CLUSTER_ID;
    write_req.attr_number = 1;
    write_req.attr_field = &attr;

    esp_zb_zcl_write_attr_cmd_req(&write_req);

    ESP_LOGI(TAG, "Time sync command sent to %s", device_name);
}

void zigbee_broadcast_time_sync(void)
{
    time_t now = time(NULL);
    if (now < 1000000000) {
        ESP_LOGW(TAG, "System time not set, skipping time broadcast");
        return;
    }

    struct tm timeinfo;
    localtime_r(&now, &timeinfo);

    ESP_LOGI(TAG, "Broadcasting time sync: %02d:%02d:%02d",
             timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);

    // Send time sync to each registered device
    if (halloween_trigger.is_bound && halloween_trigger.short_addr != 0) {
        zigbee_send_time_sync_to_device(halloween_trigger.short_addr, halloween_trigger.endpoint, "Haunted Pumpkin Scarecrow");
        halloween_trigger.time_synced = true;
        halloween_trigger.last_time_sync = now;
    }

    if (rip_tombstone.is_bound && rip_tombstone.short_addr != 0) {
        zigbee_send_time_sync_to_device(rip_tombstone.short_addr, rip_tombstone.endpoint, "RIP Tombstone");
        rip_tombstone.time_synced = true;
        rip_tombstone.last_time_sync = now;
    }
}

void trigger_rip_tombstone(void)
{
    if (rip_tombstone.is_bound && rip_tombstone.short_addr != 0) {
        time_t now = time(NULL);

        // Only update last_trigger if device is not in cooldown
        // This prevents extending cooldown on repeated trigger attempts
        bool in_cooldown = (rip_tombstone.last_trigger > 0 && (now - rip_tombstone.last_trigger) < 120);

        if (!in_cooldown) {
            ESP_LOGI(TAG, "🎃 Triggering RIP Tombstone");
            zigbee_send_on_command(rip_tombstone.short_addr, rip_tombstone.endpoint);
            rip_tombstone.last_trigger = now;
        } else {
            ESP_LOGI(TAG, "🎃 Triggering RIP Tombstone (device in cooldown, not updating timer)");
            zigbee_send_on_command(rip_tombstone.short_addr, rip_tombstone.endpoint);
        }
    } else {
        ESP_LOGW(TAG, "RIP Tombstone not bound or not registered yet");
    }
}

void trigger_halloween_decoration(void)
{
    if (halloween_trigger.is_bound && halloween_trigger.short_addr != 0) {
        time_t now = time(NULL);

        // Only update last_trigger if device is not in cooldown
        // This prevents extending cooldown on repeated trigger attempts
        bool in_cooldown = (halloween_trigger.last_trigger > 0 && (now - halloween_trigger.last_trigger) < 120);

        if (!in_cooldown) {
            ESP_LOGI(TAG, "🎃 Triggering Haunted Pumpkin Scarecrow");
            zigbee_send_on_command(halloween_trigger.short_addr, halloween_trigger.endpoint);
            halloween_trigger.last_trigger = now;
        } else {
            ESP_LOGI(TAG, "🎃 Triggering Haunted Pumpkin Scarecrow (device in cooldown, not updating timer)");
            zigbee_send_on_command(halloween_trigger.short_addr, halloween_trigger.endpoint);
        }
    } else {
        ESP_LOGW(TAG, "Haunted Pumpkin Scarecrow not bound or not registered yet");
    }
}

static esp_err_t zb_action_handler(esp_zb_core_action_callback_id_t callback_id, const void *message)
{
    esp_err_t ret = ESP_OK;

    switch (callback_id) {
        case ESP_ZB_CORE_SET_ATTR_VALUE_CB_ID: {
            const esp_zb_zcl_set_attr_value_message_t *attr_msg = (esp_zb_zcl_set_attr_value_message_t *)message;

            ESP_LOGI(TAG, "Zigbee attribute write - Cluster: 0x%04x, Attr: 0x%04x",
                     attr_msg->info.cluster, attr_msg->attribute.id);

            // Check for Trigger Request cluster (0xFC01)
            if (attr_msg->info.cluster == ZB_TRIGGER_REQUEST_CLUSTER_ID) {
                if (attr_msg->attribute.id == ZB_TRIGGER_REQUEST_ATTR_ID) {
                    uint8_t trigger_target = *(uint8_t *)attr_msg->attribute.data.value;
                    ESP_LOGI(TAG, "Received trigger request for target: %d", trigger_target);

                    // 1 = trigger scarecrow
                    if (trigger_target == 1) {
                        ESP_LOGI(TAG, "Triggering haunted pumpkin scarecrow...");
                        if (halloween_trigger.short_addr != 0 && halloween_trigger.is_bound) {
                            zigbee_send_on_command(halloween_trigger.short_addr, halloween_trigger.endpoint);
                        } else {
                            ESP_LOGW(TAG, "Scarecrow not connected, cannot trigger");
                        }
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

            // Open network for joining (255 = infinite, 0 = close)
            ESP_LOGI(TAG, "Opening network for joining (permit join = 255 seconds / infinite)");
            esp_zb_bdb_open_network(255);

            esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
        } else {
            ESP_LOGI(TAG, "Restart network formation (status: %s)", esp_err_to_name(err_status));
            esp_zb_scheduler_alarm((esp_zb_callback_t)esp_zb_bdb_start_top_level_commissioning, ESP_ZB_BDB_MODE_NETWORK_FORMATION, 1000);
        }
        break;
    case ESP_ZB_BDB_SIGNAL_STEERING:
        if (err_status == ESP_OK) {
            ESP_LOGI(TAG, "Network steering started - devices can now join");
            ESP_LOGI(TAG, "Signal strength task will auto-discover devices every 3 seconds");
        }
        break;
    case ESP_ZB_ZDO_SIGNAL_DEVICE_ANNCE:
        {
            esp_zb_zdo_signal_device_annce_params_t *dev_annce_params = (esp_zb_zdo_signal_device_annce_params_t *)esp_zb_app_signal_get_params(p_sg_p);
            uint16_t short_addr = dev_annce_params->device_short_addr;
            uint64_t ieee_addr = 0;
            memcpy(&ieee_addr, dev_annce_params->ieee_addr, sizeof(esp_zb_ieee_addr_t));

            ESP_LOGI(TAG, "Device announced: short=0x%04hx, ieee=0x%016llx", short_addr, ieee_addr);

            // Identify device by its hardcoded IEEE address
            if (ieee_addr == HALLOWEEN_TRIGGER_IEEE) {
                halloween_trigger.short_addr = short_addr;
                halloween_trigger.ieee_addr = ieee_addr;
                halloween_trigger.endpoint = 1;
                halloween_trigger.is_bound = true;
                ESP_LOGI(TAG, "Registered as Haunted Pumpkin Scarecrow device");

                // Send time sync to newly joined device
                vTaskDelay(pdMS_TO_TICKS(500)); // Small delay for device to be ready
                zigbee_send_time_sync_to_device(short_addr, halloween_trigger.endpoint, "Haunted Pumpkin Scarecrow");
                halloween_trigger.time_synced = true;
                halloween_trigger.last_time_sync = time(NULL);

                // Notify TinyS3 of device join
                uart_send_device_event(CMD_DEVICE_JOINED, DEVICE_ID_HALLOWEEN);
            } else if (ieee_addr == RIP_TOMBSTONE_IEEE && RIP_TOMBSTONE_IEEE != 0) {
                rip_tombstone.short_addr = short_addr;
                rip_tombstone.ieee_addr = ieee_addr;
                rip_tombstone.endpoint = 1;
                rip_tombstone.is_bound = true;
                ESP_LOGI(TAG, "Registered as RIP Tombstone device");

                // Send time sync to newly joined device
                vTaskDelay(pdMS_TO_TICKS(500)); // Small delay for device to be ready
                zigbee_send_time_sync_to_device(short_addr, rip_tombstone.endpoint, "RIP Tombstone");
                rip_tombstone.time_synced = true;
                rip_tombstone.last_time_sync = time(NULL);

                // Notify TinyS3 of device join
                uart_send_device_event(CMD_DEVICE_JOINED, DEVICE_ID_RIP);
            } else {
                ESP_LOGW(TAG, "Unknown device joined: ieee=0x%016llx (not in hardcoded list)", ieee_addr);
            }
        }
        break;

    case ESP_ZB_ZDO_SIGNAL_LEAVE_INDICATION:
        if (err_status == ESP_OK) {
            esp_zb_zdo_signal_leave_indication_params_t *leave_params = (esp_zb_zdo_signal_leave_indication_params_t *)esp_zb_app_signal_get_params(p_sg_p);
            uint64_t ieee_addr = 0;
            memcpy(&ieee_addr, leave_params->device_addr, sizeof(esp_zb_ieee_addr_t));

            ESP_LOGI(TAG, "Device left network: short=0x%04hx, ieee=0x%016llx", leave_params->short_addr, ieee_addr);

            // Mark device as disconnected
            if (ieee_addr == HALLOWEEN_TRIGGER_IEEE) {
                halloween_trigger.is_bound = false;
                halloween_trigger.short_addr = 0;
                halloween_trigger.time_synced = false;
                ESP_LOGI(TAG, "Haunted Pumpkin Scarecrow disconnected");
                uart_send_device_event(CMD_DEVICE_LEFT, DEVICE_ID_HALLOWEEN);
            } else if (ieee_addr == RIP_TOMBSTONE_IEEE) {
                rip_tombstone.is_bound = false;
                rip_tombstone.short_addr = 0;
                rip_tombstone.time_synced = false;
                ESP_LOGI(TAG, "RIP Tombstone disconnected");
                uart_send_device_event(CMD_DEVICE_LEFT, DEVICE_ID_RIP);
            }
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
    // CRITICAL: Hardcoded network credentials for production resilience
    // These values ensure the coordinator forms the SAME network after flash erase
    // DO NOT CHANGE these values once devices are deployed!

    // Fixed Extended PAN ID (8 bytes) - uniquely identifies this Zigbee network
    uint8_t ext_pan_id[8] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE};

    // Fixed Network Key (16 bytes) - encryption key for the network
    // WARNING: In production, use a cryptographically random key!
    uint8_t nwk_key[16] = {0x5A, 0x69, 0x67, 0x62, 0x65, 0x65, 0x57, 0x65,
                           0x65, 0x6E, 0x32, 0x30, 0x32, 0x35, 0x21, 0x21};

    // Configure as coordinator
    esp_zb_cfg_t zb_nwk_cfg;
    zb_nwk_cfg.esp_zb_role = ESP_ZB_DEVICE_TYPE_COORDINATOR;
    zb_nwk_cfg.install_code_policy = false;
    zb_nwk_cfg.nwk_cfg.zczr_cfg.max_children = 10;

    esp_zb_init(&zb_nwk_cfg);

    // Set the fixed extended PAN ID and network key
    esp_zb_set_extended_pan_id(ext_pan_id);
    esp_zb_secur_network_key_set(nwk_key);

    // Set the primary channel to channel 15
    esp_zb_set_primary_network_channel_set(ESP_ZB_PRIMARY_CHANNEL_MASK);

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

    // Add trigger request cluster (0xFC01) - SERVER role to receive requests from end devices
    esp_zb_attribute_list_t *trigger_request_cluster = esp_zb_zcl_attr_list_create(ZB_TRIGGER_REQUEST_CLUSTER_ID);
    uint8_t trigger_value = 0;
    esp_zb_custom_cluster_add_custom_attr(trigger_request_cluster, ZB_TRIGGER_REQUEST_ATTR_ID, ESP_ZB_ZCL_ATTR_TYPE_U8,
                                          ESP_ZB_ZCL_ATTR_ACCESS_READ_WRITE, &trigger_value);
    esp_zb_cluster_list_add_custom_cluster(cluster_list, trigger_request_cluster, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);

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

                        case CMD_STATUS_REQUEST:
                            ESP_LOGI(TAG, "UART received: CMD_STATUS_REQUEST");
                            uart_send_device_status();
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

                                // Broadcast time to all Zigbee end devices
                                ESP_LOGI(TAG, "Forwarding time to Zigbee devices...");
                                vTaskDelay(pdMS_TO_TICKS(100)); // Small delay for Zigbee stack
                                zigbee_broadcast_time_sync();
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
    rip_tombstone.is_bound = false;  // Will be set when device announces

    strcpy(halloween_trigger.name, "Haunted Pumpkin Scarecrow");
    halloween_trigger.endpoint = 1;
    halloween_trigger.is_bound = false;  // Will be set when device announces

    // Start UART handler task
    xTaskCreate(uart_handler_task, "UART_handler", 2048, NULL, 10, NULL);

    // Start Zigbee coordinator
    ESP_LOGI(TAG, "Starting Zigbee coordinator...");
    ESP_LOGI(TAG, "   Channel: %d (2.4GHz @ ~%d MHz)", ZIGBEE_CHANNEL, 2405 + 5 * ZIGBEE_CHANNEL);
    xTaskCreate(esp_zb_task, "Zigbee_main", 4096, NULL, 5, NULL);

    // Start signal strength monitoring task
    xTaskCreate(signal_strength_task, "signal_monitor", 2048, NULL, 3, NULL);
    ESP_LOGI(TAG, "Signal strength monitoring started");

    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  System Ready!                               ║");
    ESP_LOGI(TAG, "║  - Zigbee coordinator active                 ║");
    ESP_LOGI(TAG, "║  - UART receiver listening for commands      ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Main loop - periodic status and time sync
    uint32_t time_sync_counter = 0;
    uint32_t status_counter = 0;
    const uint32_t TIME_SYNC_INTERVAL = 300; // Broadcast time every 5 minutes (300 seconds)
    const uint32_t STATUS_UPDATE_INTERVAL = 30; // Send status to TinyS3 every 30 seconds

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000)); // Check every 10 seconds

        time_t now = time(NULL);
        struct tm timeinfo;
        localtime_r(&now, &timeinfo);
        char time_str[64];
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
        ESP_LOGI(TAG, "Time: %s | RIP sync: %s | Halloween sync: %s",
                 time_str,
                 rip_tombstone.time_synced ? "✓" : "✗",
                 halloween_trigger.time_synced ? "✓" : "✗");

        // Periodic time sync broadcast (every 5 minutes)
        time_sync_counter += 10;
        if (time_sync_counter >= TIME_SYNC_INTERVAL) {
            ESP_LOGI(TAG, "Periodic time sync broadcast to Zigbee devices...");
            zigbee_broadcast_time_sync();
            time_sync_counter = 0;
        }

        // Periodic status update to TinyS3 (every 30 seconds)
        status_counter += 10;
        if (status_counter >= STATUS_UPDATE_INTERVAL) {
            uart_send_device_status();
            status_counter = 0;
        }
    }
}
