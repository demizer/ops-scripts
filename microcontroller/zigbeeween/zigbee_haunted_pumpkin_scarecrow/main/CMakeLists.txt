idf_component_register(SRCS "main.c"
                    INCLUDE_DIRS "." "../managed_components/espressif__esp-zigbee-lib/include" "../managed_components/espressif__esp-zboss-lib/include"
                    REQUIRES driver esp_timer nvs_flash
                    PRIV_REQUIRES espressif__esp-zigbee-lib espressif__esp-zboss-lib)
