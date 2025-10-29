#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_sntp.h"
#include "esp_http_server.h"
#include "nvs_flash.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_zigbee_core.h"
#include "lwip/err.h"
#include "lwip/sys.h"
#include "lwip/sockets.h"
#include "lwip/dns.h"
#include "lwip/netdb.h"
#include "lwip/etharp.h"
#include "ping/ping_sock.h"

static const char *TAG = "zigbee_controller";

// WiFi credentials (configure these!)
#define WIFI_SSID      CONFIG_ESP_WIFI_SSID
#define WIFI_PASS      CONFIG_ESP_WIFI_PASSWORD

// Pin definitions for TinyC6
#define PIR_PIN GPIO_NUM_15      // PIR motion sensor (GPIO9 is boot strapping pin!)
#define LED_PIN GPIO_NUM_8       // Built-in NeoPixel (WS2812)
#define I2C_SDA_PIN GPIO_NUM_6   // OLED SDA
#define I2C_SCL_PIN GPIO_NUM_7   // OLED SCL
#define OLED_ADDR 0x3C

// I2C configuration
#define I2C_MASTER_NUM I2C_NUM_0
#define I2C_MASTER_FREQ_HZ 100000

// Zigbee configuration
// Use channel 15 (2425 MHz) to avoid WiFi interference
// WiFi channel 1 = 2412 MHz, channel 10 = 2457 MHz
// Zigbee channel 15 avoids both
#define ZIGBEE_CHANNEL 15
#define ESP_ZB_PRIMARY_CHANNEL_MASK (1 << ZIGBEE_CHANNEL)

// Event group bits
#define WIFI_CONNECTED_BIT BIT0

// Global state
static EventGroupHandle_t s_wifi_event_group;
static int s_retry_num = 0;
static httpd_handle_t server = NULL;
static bool pir_motion_detected = false;

// Device tracking (IEEE addresses of bound devices)
typedef struct {
    uint64_t ieee_addr;
    uint8_t endpoint;
    char name[32];
    bool is_bound;
} zigbee_device_t;

static zigbee_device_t rip_tombstone = {0};
static zigbee_device_t halloween_trigger = {0};

// Time sync
static bool time_synced = false;

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

// Simple text display (first line only for simplicity)
void oled_print(const char *text)
{
    oled_clear();

    // Basic 8x8 font would go here - for now just show status via ESP_LOGI
    ESP_LOGI(TAG, "OLED: %s", text);
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

    // Set timezone to Los Angeles (PST8PDT)
    setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);
    tzset();

    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);

    // Set NTP server using IP address string (local router)
    esp_sntp_setservername(0, "192.168.5.1");

    sntp_set_time_sync_notification_cb(time_sync_notification_cb);

    ESP_LOGI(TAG, "📡 Starting SNTP client...");
    ESP_LOGI(TAG, "   NTP server: 192.168.5.1 (local router)");
    ESP_LOGI(TAG, "   Sync mode: POLL");

    esp_sntp_init();

    ESP_LOGI(TAG, "⏳ SNTP initialized, waiting for time sync...");
    ESP_LOGI(TAG, "   (This can take 10-30 seconds)");
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

// Ping callbacks
static void on_ping_success(esp_ping_handle_t hdl, void *args)
{
    uint8_t ttl;
    uint16_t seqno;
    uint32_t elapsed_time, recv_len;
    ip_addr_t target_addr;
    esp_ping_get_profile(hdl, ESP_PING_PROF_SEQNO, &seqno, sizeof(seqno));
    esp_ping_get_profile(hdl, ESP_PING_PROF_TTL, &ttl, sizeof(ttl));
    esp_ping_get_profile(hdl, ESP_PING_PROF_IPADDR, &target_addr, sizeof(target_addr));
    esp_ping_get_profile(hdl, ESP_PING_PROF_SIZE, &recv_len, sizeof(recv_len));
    esp_ping_get_profile(hdl, ESP_PING_PROF_TIMEGAP, &elapsed_time, sizeof(elapsed_time));
    ESP_LOGI(TAG, "   ✓ %lu bytes from " IPSTR " icmp_seq=%u ttl=%u time=%lu ms",
             recv_len, IP2STR(&target_addr.u_addr.ip4), seqno, ttl, elapsed_time);
}

static void on_ping_timeout(esp_ping_handle_t hdl, void *args)
{
    uint16_t seqno;
    ip_addr_t target_addr;
    esp_ping_get_profile(hdl, ESP_PING_PROF_SEQNO, &seqno, sizeof(seqno));
    esp_ping_get_profile(hdl, ESP_PING_PROF_IPADDR, &target_addr, sizeof(target_addr));
    ESP_LOGW(TAG, "   ✗ Timeout from " IPSTR " icmp_seq=%u", IP2STR(&target_addr.u_addr.ip4), seqno);
}

static void on_ping_end(esp_ping_handle_t hdl, void *args)
{
    uint32_t transmitted, received, total_time_ms;
    esp_ping_get_profile(hdl, ESP_PING_PROF_REQUEST, &transmitted, sizeof(transmitted));
    esp_ping_get_profile(hdl, ESP_PING_PROF_REPLY, &received, sizeof(received));
    esp_ping_get_profile(hdl, ESP_PING_PROF_DURATION, &total_time_ms, sizeof(total_time_ms));

    uint32_t loss = transmitted - received;
    ESP_LOGI(TAG, "   --- ping statistics ---");
    ESP_LOGI(TAG, "   %lu packets transmitted, %lu received, %lu%% packet loss, time %lu ms",
             transmitted, received, (loss * 100) / transmitted, total_time_ms);
}

// Test network connectivity by pinging gateway
void test_network_connectivity(void)
{
    ESP_LOGI(TAG, "🔍 Testing network connectivity...");

    // Get gateway IP
    esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    esp_netif_ip_info_t ip_info;
    esp_netif_get_ip_info(netif, &ip_info);

    ESP_LOGI(TAG, "   Gateway IP: " IPSTR, IP2STR(&ip_info.gw));
    ESP_LOGI(TAG, "   Attempting to ping gateway (3 packets)...");

    // Configure ping
    esp_ping_config_t ping_config = ESP_PING_DEFAULT_CONFIG();
    ping_config.target_addr.u_addr.ip4.addr = ip_info.gw.addr;
    ping_config.target_addr.type = IPADDR_TYPE_V4;
    ping_config.count = 3;
    ping_config.interval_ms = 1000;
    ping_config.timeout_ms = 5000;

    // Callbacks for ping results
    esp_ping_callbacks_t cbs = {
        .on_ping_success = on_ping_success,
        .on_ping_timeout = on_ping_timeout,
        .on_ping_end = on_ping_end,
        .cb_args = NULL
    };

    esp_ping_handle_t ping;
    esp_err_t ret = esp_ping_new_session(&ping_config, &cbs, &ping);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "   Ping session created, starting...");
        esp_ping_start(ping);
        vTaskDelay(pdMS_TO_TICKS(5000)); // Wait for pings to complete
        esp_ping_stop(ping);
        esp_ping_delete_session(ping);
    } else {
        ESP_LOGE(TAG, "❌ Failed to create ping session: %s", esp_err_to_name(ret));
    }
}

// Wait for NTP sync with timeout - HALT program if time cannot be determined
void wait_for_ntp_sync(uint32_t timeout_seconds)
{
    ESP_LOGI(TAG, "⏳ Waiting for NTP time synchronization...");
    ESP_LOGI(TAG, "   Timeout: %lu seconds", timeout_seconds);
    ESP_LOGI(TAG, "   (Time synchronization is CRITICAL for this application)");

    uint32_t elapsed = 0;
    while (!time_synced && elapsed < timeout_seconds) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        elapsed++;

        if (elapsed % 5 == 0) {
            ESP_LOGI(TAG, "   Still waiting for NTP sync... (%lu/%lu seconds)", elapsed, timeout_seconds);
        }
    }

    if (time_synced) {
        time_t now;
        struct tm timeinfo;
        time(&now);
        localtime_r(&now, &timeinfo);

        char time_str[64];
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);

        ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
        ESP_LOGI(TAG, "║  ✓ TIME SYNCHRONIZED                         ║");
        ESP_LOGI(TAG, "║                                              ║");
        ESP_LOGI(TAG, "║  %s                ║", time_str);
        ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");
    } else {
        ESP_LOGE(TAG, "╔══════════════════════════════════════════════╗");
        ESP_LOGE(TAG, "║  ❌ FATAL ERROR: NTP TIME SYNC FAILED        ║");
        ESP_LOGE(TAG, "║                                              ║");
        ESP_LOGE(TAG, "║  Timeout after %lu seconds                    ║", timeout_seconds);
        ESP_LOGE(TAG, "║  NTP server: 192.168.5.1                     ║");
        ESP_LOGE(TAG, "║                                              ║");
        ESP_LOGE(TAG, "║  Accurate timekeeping is CRITICAL for        ║");
        ESP_LOGE(TAG, "║  this application. Program HALTED.           ║");
        ESP_LOGE(TAG, "║                                              ║");
        ESP_LOGE(TAG, "║  Please verify:                              ║");
        ESP_LOGE(TAG, "║  1. Device has network connectivity          ║");
        ESP_LOGE(TAG, "║  2. NTP server 192.168.5.1 is reachable      ║");
        ESP_LOGE(TAG, "║  3. Firewall allows NTP traffic (UDP 123)    ║");
        ESP_LOGE(TAG, "╚══════════════════════════════════════════════╝");

        // HALT the program - user explicitly requires this
        ESP_LOGE(TAG, "HALTING PROGRAM DUE TO NTP SYNC FAILURE");
        vTaskDelay(pdMS_TO_TICKS(1000));
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

        // Always retry - no limit
        s_retry_num++;
        ESP_LOGI(TAG, "Reconnecting to WiFi (attempt %d)...", s_retry_num);
        vTaskDelay(pdMS_TO_TICKS(1000));  // Wait 1 second before retry
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "✓ WiFi connected successfully!");
        ESP_LOGI(TAG, "✓ IP Address: " IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "✓ Netmask:    " IPSTR, IP2STR(&event->ip_info.netmask));
        ESP_LOGI(TAG, "✓ Gateway:    " IPSTR, IP2STR(&event->ip_info.gw));

        // Get WiFi info including MAC address
        wifi_ap_record_t ap_info;
        if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK) {
            ESP_LOGI(TAG, "✓ Connected to AP: %s", ap_info.ssid);
            ESP_LOGI(TAG, "✓ AP MAC (BSSID): %02x:%02x:%02x:%02x:%02x:%02x",
                     ap_info.bssid[0], ap_info.bssid[1], ap_info.bssid[2],
                     ap_info.bssid[3], ap_info.bssid[4], ap_info.bssid[5]);
        }

        // Get our own MAC address
        uint8_t mac[6];
        esp_wifi_get_mac(WIFI_IF_STA, mac);
        ESP_LOGI(TAG, "✓ Device MAC:     %02x:%02x:%02x:%02x:%02x:%02x",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

        // Send gratuitous ARP to announce our presence on the network
        ESP_LOGI(TAG, "📡 Sending gratuitous ARP to announce IP...");
        esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
        if (netif) {
            ESP_LOGI(TAG, "   Network interface ready for traffic");
        }

        s_retry_num = 0;
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

void wifi_scan_networks(void)
{
    ESP_LOGI(TAG, "📡 Scanning for WiFi networks (2.4GHz only)...");

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

    if (ap_count == 0) {
        ESP_LOGW(TAG, "No WiFi networks found!");
        return;
    }

    wifi_ap_record_t *ap_list = malloc(sizeof(wifi_ap_record_t) * ap_count);
    if (ap_list == NULL) {
        ESP_LOGE(TAG, "Failed to allocate memory for AP list");
        return;
    }

    ESP_ERROR_CHECK(esp_wifi_scan_get_ap_records(&ap_count, ap_list));

    ESP_LOGI(TAG, "Found %d WiFi networks:", ap_count);
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

        // Determine band: 1-14 is 2.4GHz, 36+ is 5GHz
        const char *band = (ap_list[i].primary <= 14) ? "2.4G" : "5G";

        ESP_LOGI(TAG, "║ %2d  %-30s %3d  %-5s %4d  %-11s ║",
                 i + 1, ap_list[i].ssid, ap_list[i].primary, band,
                 ap_list[i].rssi, auth_mode);
    }

    ESP_LOGI(TAG, "╚══════════════════════════════════════════════════════════════════╝");

    free(ap_list);
}

void wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_LOGI(TAG, "🔧 Initializing WiFi...");
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_t *sta_netif = esp_netif_create_default_wifi_sta();

    // Set hostname for DHCP
    ESP_ERROR_CHECK(esp_netif_set_hostname(sta_netif, "zigbeeween"));
    ESP_LOGI(TAG, "📛 Hostname set to: zigbeeween");

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

    ESP_LOGI(TAG, "📡 Note: ESP32-C6 only supports 2.4GHz WiFi (not 5GHz)");
    ESP_LOGI(TAG, "🔌 Starting WiFi and connecting to '%s'...", WIFI_SSID);

    // Start WiFi
    ESP_ERROR_CHECK(esp_wifi_start());

    // Wait for WiFi to initialize
    vTaskDelay(pdMS_TO_TICKS(200));

    // Disconnect to stop auto-connect so we can scan
    esp_wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(100));

    // Scan for available networks (helps WiFi find APs)
    ESP_LOGI(TAG, "📡 Scanning for WiFi networks (2.4GHz only)...");
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
// Zigbee Coordinator Functions
// ============================================================================

void zigbee_send_on_command(uint64_t ieee_addr, uint8_t endpoint)
{
    ESP_LOGI(TAG, "Sending Zigbee ON command to device 0x%llx endpoint %d",
             ieee_addr, endpoint);

    esp_zb_zcl_on_off_cmd_t cmd_req;
    cmd_req.zcl_basic_cmd.dst_addr_u.addr_short = 0xFFFF; // Broadcast or specific address
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
        oled_print("RIP TRIGGER!");
        zigbee_send_on_command(rip_tombstone.ieee_addr, rip_tombstone.endpoint);
    } else {
        ESP_LOGW(TAG, "RIP Tombstone not bound");
    }
}

void trigger_halloween_decoration(void)
{
    if (halloween_trigger.is_bound) {
        ESP_LOGI(TAG, "🎃 Triggering Halloween Decoration");
        oled_print("HALLOWEEN!");
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
    // Configure as coordinator (similar to ESP_ZB_ZED_CONFIG but for coordinator)
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

    ESP_LOGI(TAG, "Starting Zigbee coordinator");
    ESP_ERROR_CHECK(esp_zb_start(false));
    esp_zb_main_loop_iteration();
}

// ============================================================================
// HTTP Web Server Handlers
// ============================================================================

// Serve the main HTML page
static esp_err_t root_handler(httpd_req_t *req)
{
    ESP_LOGI(TAG, "HTTP GET /");

    char time_str[64];
    get_current_time_str(time_str, sizeof(time_str));

    httpd_resp_set_type(req, "text/html");

    // Send HTML in chunks to avoid stack overflow
    httpd_resp_sendstr_chunk(req,
        "<!DOCTYPE html><html><head><title>Zigbee Halloween Controller</title>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<style>"
        "body{font-family:Arial;background:#1a1a1a;color:#fff;padding:20px;text-align:center}"
        "h1{color:#ff6b00}h2{color:#ff8c00}"
        ".status{background:#2a2a2a;padding:15px;margin:20px 0;border-radius:10px}"
        ".button{background:#ff6b00;color:#fff;border:none;padding:15px 30px;font-size:18px;"
        "margin:10px;border-radius:5px;cursor:pointer;min-width:200px}"
        ".button:hover{background:#ff8c00}"
        ".button:active{background:#cc5500}"
        ".motion{color:#00ff00;font-weight:bold}"
        ".time{color:#88aaff;font-size:14px}"
        "</style></head><body>"
        "<h1>🎃 Zigbee Halloween Controller 🎃</h1>"
        "<div class='status'>");

    char buf[128];
    snprintf(buf, sizeof(buf), "<p class='time'>%s</p>", time_str);
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p>PIR Motion: <span class='motion'>%s</span></p>",
             pir_motion_detected ? "DETECTED" : "None");
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p>RIP Tombstone: %s</p>",
             rip_tombstone.is_bound ? "Connected" : "Not bound");
    httpd_resp_sendstr_chunk(req, buf);

    snprintf(buf, sizeof(buf), "<p>Halloween Trigger: %s</p>",
             halloween_trigger.is_bound ? "Connected" : "Not bound");
    httpd_resp_sendstr_chunk(req, buf);

    httpd_resp_sendstr_chunk(req,
        "</div>"
        "<h2>Manual Control</h2>"
        "<form method='POST' action='/trigger/rip'>"
        "<button class='button' type='submit'>🪦 Trigger RIP Tombstone</button>"
        "</form>"
        "<form method='POST' action='/trigger/halloween'>"
        "<button class='button' type='submit'>🎃 Trigger Halloween</button>"
        "</form>"
        "<form method='POST' action='/trigger/both'>"
        "<button class='button' type='submit'>👻 Trigger BOTH</button>"
        "</form>"
        "</body></html>");

    // End chunked response
    httpd_resp_sendstr_chunk(req, NULL);

    return ESP_OK;
}

static esp_err_t trigger_rip_handler(httpd_req_t *req)
{
    trigger_rip_tombstone();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static esp_err_t trigger_halloween_handler(httpd_req_t *req)
{
    trigger_halloween_decoration();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static esp_err_t trigger_both_handler(httpd_req_t *req)
{
    trigger_rip_tombstone();
    vTaskDelay(pdMS_TO_TICKS(100));
    trigger_halloween_decoration();
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", "/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

httpd_handle_t start_webserver(void)
{
    httpd_handle_t server = NULL;
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.lru_purge_enable = true;

    ESP_LOGI(TAG, "🌐 Starting HTTP server...");
    ESP_LOGI(TAG, "   Port: %d", config.server_port);
    ESP_LOGI(TAG, "   Max open sockets: %d", config.max_open_sockets);
    ESP_LOGI(TAG, "   Backlog connections: %d", config.backlog_conn);

    esp_err_t ret = httpd_start(&server, &config);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "✓ HTTP server started successfully!");
        ESP_LOGI(TAG, "   Server handle: %p", server);
        // Register URI handlers
        httpd_uri_t root = {
            .uri       = "/",
            .method    = HTTP_GET,
            .handler   = root_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &root);

        httpd_uri_t trigger_rip = {
            .uri       = "/trigger/rip",
            .method    = HTTP_POST,
            .handler   = trigger_rip_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &trigger_rip);

        httpd_uri_t trigger_halloween = {
            .uri       = "/trigger/halloween",
            .method    = HTTP_POST,
            .handler   = trigger_halloween_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &trigger_halloween);

        httpd_uri_t trigger_both = {
            .uri       = "/trigger/both",
            .method    = HTTP_POST,
            .handler   = trigger_both_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &trigger_both);

        ESP_LOGI(TAG, "✓ All URI handlers registered:");
        ESP_LOGI(TAG, "   GET  /");
        ESP_LOGI(TAG, "   POST /trigger/rip");
        ESP_LOGI(TAG, "   POST /trigger/halloween");
        ESP_LOGI(TAG, "   POST /trigger/both");

        return server;
    }

    ESP_LOGE(TAG, "❌ Error starting HTTP server! Error code: 0x%x", ret);
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
                oled_print("MOTION!");

                // Auto-trigger both devices on motion
                trigger_rip_tombstone();
                vTaskDelay(pdMS_TO_TICKS(200));
                trigger_halloween_decoration();
            } else {
                ESP_LOGI(TAG, "⚫ Motion stopped");
                oled_print("Ready...");
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
    ESP_LOGI(TAG, "║  Zigbee Halloween Controller - TinyC6       ║");
    ESP_LOGI(TAG, "║  ESP32-C6 Zigbee Coordinator with Web UI    ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Disable verbose logging to prevent watchdog timeout
    esp_log_level_set("wifi", ESP_LOG_INFO);
    esp_log_level_set("lwip", ESP_LOG_WARN);
    esp_log_level_set("esp_netif_lwip", ESP_LOG_INFO);

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Initialize hardware
    setup_i2c();
    oled_init();
    oled_print("Starting...");
    setup_pir_sensor();

    // Initialize device records
    strcpy(rip_tombstone.name, "RIP Tombstone");
    rip_tombstone.endpoint = 1;
    rip_tombstone.is_bound = true; // Set to true when devices pair

    strcpy(halloween_trigger.name, "Halloween Trigger");
    halloween_trigger.endpoint = 1;
    halloween_trigger.is_bound = true; // Set to true when devices pair

    // Initialize WiFi
    ESP_LOGI(TAG, "Connecting to WiFi...");
    oled_print("WiFi...");
    wifi_init_sta();

    // Allow network stack to fully stabilize after connection
    ESP_LOGI(TAG, "⏸️  Allowing network stack to stabilize...");
    vTaskDelay(pdMS_TO_TICKS(2000));

    // Test network connectivity by pinging gateway
    test_network_connectivity();

    // Initialize NTP and WAIT for sync (CRITICAL - program halts if sync fails)
    initialize_sntp();
    oled_print("Time sync...");
    wait_for_ntp_sync(60); // 60 second timeout - will ABORT if sync fails

    // Start web server
    ESP_LOGI(TAG, "Starting web server...");
    oled_print("Web server...");
    server = start_webserver();
    if (server) {
        // Get current IP address
        esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
        esp_netif_ip_info_t ip_info;
        esp_netif_get_ip_info(netif, &ip_info);

        ESP_LOGI(TAG, "✓ Web server started successfully");
        ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
        ESP_LOGI(TAG, "║  Web Interface Ready!                        ║");
        ESP_LOGI(TAG, "║                                              ║");
        ESP_LOGI(TAG, "║  URL: http://" IPSTR "/               ║", IP2STR(&ip_info.ip));
        ESP_LOGI(TAG, "║                                              ║");
        ESP_LOGI(TAG, "║  Test connectivity:                          ║");
        ESP_LOGI(TAG, "║    ping " IPSTR "                     ║", IP2STR(&ip_info.ip));
        ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");
    }

    // Start Zigbee coordinator
    ESP_LOGI(TAG, "Starting Zigbee coordinator...");
    ESP_LOGI(TAG, "   Channel: %d (2.4GHz @ ~%d MHz)", ZIGBEE_CHANNEL, 2405 + 5 * ZIGBEE_CHANNEL);
    ESP_LOGI(TAG, "   Note: Using channel %d to avoid WiFi interference", ZIGBEE_CHANNEL);
    oled_print("Zigbee...");
    xTaskCreate(esp_zb_task, "Zigbee_main", 4096, NULL, 5, NULL);

    // Start PIR monitoring
    xTaskCreate(pir_monitor_task, "PIR_monitor", 2048, NULL, 4, NULL);

    // Display ready message
    vTaskDelay(pdMS_TO_TICKS(1000));
    oled_print("Ready!");

    ESP_LOGI(TAG, "╔══════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║  System Ready!                               ║");
    ESP_LOGI(TAG, "║  - Zigbee coordinator active                 ║");
    ESP_LOGI(TAG, "║  - Web interface running                     ║");
    ESP_LOGI(TAG, "║  - PIR motion detection enabled              ║");
    ESP_LOGI(TAG, "╚══════════════════════════════════════════════╝");

    // Main loop - update display periodically
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));

        char time_str[64];
        get_current_time_str(time_str, sizeof(time_str));
        ESP_LOGI(TAG, "Time: %s, Motion: %s",
                 time_str,
                 pir_motion_detected ? "YES" : "NO");
    }
}
