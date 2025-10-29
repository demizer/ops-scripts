#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#include "led_strip.h"

static const char *TAG = "rip_tombstone";

// Pin definitions
#define PIR_PIN GPIO_NUM_18
#define LED_PIN GPIO_NUM_15  // Built-in yellow LED on Xiao ESP32-C6
#define NEOPIXEL_PIN GPIO_NUM_19  // NeoPixel strip data pin
#define NEOPIXEL_COUNT 10  // 10 LEDs in the strip

// LED strip handle
static led_strip_handle_t neopixel_strip;

void setup_pir(void)
{
    // Configure PIR sensor pin as input with pull-down
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
    // Configure LED pin as output
    gpio_config_t led_conf = {
        .pin_bit_mask = (1ULL << LED_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&led_conf);

    // Turn off LED initially
    gpio_set_level(LED_PIN, 0);

    ESP_LOGI(TAG, "Yellow LED initialized on GPIO%d", LED_PIN);
}

void setup_neopixels(void)
{
    // Configure NeoPixel strip (WS2812B)
    led_strip_config_t strip_config = {
        .strip_gpio_num = NEOPIXEL_PIN,
        .max_leds = NEOPIXEL_COUNT,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,  // NeoPixels use GRB format
        .led_model = LED_MODEL_WS2812,
        .flags.invert_out = false,
    };

    led_strip_rmt_config_t rmt_config = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = 10 * 1000 * 1000, // 10MHz
        .flags.with_dma = false,
    };

    ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &neopixel_strip));

    // Turn off all NeoPixels initially
    led_strip_clear(neopixel_strip);

    ESP_LOGI(TAG, "NeoPixel strip initialized on GPIO%d (%d LEDs)", NEOPIXEL_PIN, NEOPIXEL_COUNT);
}

void blink_neopixels_red(void)
{
    ESP_LOGI(TAG, "🔴 Blinking NeoPixels red 20 times!");

    for (int blink = 0; blink < 20; blink++) {
        // Turn all LEDs red
        for (int i = 0; i < NEOPIXEL_COUNT; i++) {
            led_strip_set_pixel(neopixel_strip, i, 255, 0, 0);  // GRB: Red (G=255, R=0, B=0)
        }
        led_strip_refresh(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(150));  // On for 150ms

        // Turn all LEDs off
        led_strip_clear(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(150));  // Off for 150ms
    }

    ESP_LOGI(TAG, "Blink complete");
}

void blink_neopixels_rainbow(void)
{
    ESP_LOGI(TAG, "🌈 RAINBOW SHOW! Blinking NeoPixels random rainbow 50 times!");

    for (int blink = 0; blink < 50; blink++) {
        // Turn all LEDs to random rainbow colors
        for (int i = 0; i < NEOPIXEL_COUNT; i++) {
            // Generate random rainbow color
            int color = esp_random() % 6;
            uint8_t r = 0, g = 0, b = 0;

            switch(color) {
                case 0: r = 255; g = 0;   b = 0;   break; // Red
                case 1: r = 255; g = 127; b = 0;   break; // Orange
                case 2: r = 255; g = 255; b = 0;   break; // Yellow
                case 3: r = 0;   g = 255; b = 0;   break; // Green
                case 4: r = 0;   g = 0;   b = 255; break; // Blue
                case 5: r = 128; g = 0;   b = 255; break; // Purple
            }

            led_strip_set_pixel(neopixel_strip, i, g, r, b);  // GRB format
        }
        led_strip_refresh(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(75));  // On for 75ms (faster!)

        // Turn all LEDs off
        led_strip_clear(neopixel_strip);
        vTaskDelay(pdMS_TO_TICKS(75));  // Off for 75ms (faster!)
    }

    ESP_LOGI(TAG, "Rainbow show complete!");
}

void app_main(void)
{
    ESP_LOGI(TAG, "RIP Tombstone - Xiao ESP32-C6 Halloween Project");
    ESP_LOGI(TAG, "Chip: ESP32-C6 (RISC-V)");
    ESP_LOGI(TAG, "PIR Motion Detector with NeoPixel Strip");
    ESP_LOGI(TAG, "Starting...");

    // Initialize hardware
    setup_pir();
    setup_led();
    setup_neopixels();

    ESP_LOGI(TAG, "Warming up PIR sensor (30 seconds)...");
    vTaskDelay(pdMS_TO_TICKS(30000));
    ESP_LOGI(TAG, "PIR sensor ready!");

    bool last_motion = false;
    bool currently_blinking = false;
    int motion_count = 0;
    int64_t first_motion_time = 0;
    int64_t last_motion_time = 0;

    while (1) {
        // Read PIR sensor
        bool motion_detected = gpio_get_level(PIR_PIN);
        int64_t current_time = esp_timer_get_time() / 1000000;  // Convert to seconds

        // Check if 30 seconds have passed since last motion - reset counter
        if (motion_count > 0 && last_motion_time > 0 && !currently_blinking) {
            if ((current_time - last_motion_time) > 30) {
                ESP_LOGI(TAG, "⏰ No motion for 30s - Resetting counter (was %d/3)", motion_count);
                motion_count = 0;
                first_motion_time = 0;
                last_motion_time = 0;
            }
        }

        // Update LED based on motion
        if (motion_detected) {
            // Turn on yellow LED for motion detected
            gpio_set_level(LED_PIN, 1);

            if (!last_motion && !currently_blinking) {
                // Check if this is the first motion or if we need to reset the counter
                if (motion_count == 0) {
                    first_motion_time = current_time;
                    motion_count = 1;
                    last_motion_time = current_time;
                    ESP_LOGI(TAG, "💡 MOTION DETECTED! Count: 1/3");
                } else {
                    // Check if we're still within 1.5 minute window (90 seconds)
                    if ((current_time - first_motion_time) <= 90) {
                        motion_count++;
                        last_motion_time = current_time;
                        ESP_LOGI(TAG, "💡 MOTION DETECTED! Count: %d/3", motion_count);
                    } else {
                        // Reset counter if more than 1.5 minutes has passed
                        ESP_LOGI(TAG, "⏰ Timer reset (>90s). Starting new count.");
                        first_motion_time = current_time;
                        motion_count = 1;
                        last_motion_time = current_time;
                        ESP_LOGI(TAG, "💡 MOTION DETECTED! Count: 1/3");
                    }
                }

                currently_blinking = true;

                // Trigger appropriate light show based on count
                if (motion_count >= 3) {
                    ESP_LOGI(TAG, "🎉 THREE MOTIONS IN 90 SECONDS! RAINBOW SHOW TIME!");
                    blink_neopixels_rainbow();
                    // Reset counter after rainbow show
                    motion_count = 0;
                    first_motion_time = 0;
                    last_motion_time = 0;
                } else {
                    blink_neopixels_red();
                }

                currently_blinking = false;
            }
        } else {
            // Turn off LED when no motion
            gpio_set_level(LED_PIN, 0);

            if (last_motion) {
                ESP_LOGI(TAG, "⚫ No motion");
            }
        }

        last_motion = motion_detected;
        vTaskDelay(pdMS_TO_TICKS(100));  // Check every 100ms
    }
}
