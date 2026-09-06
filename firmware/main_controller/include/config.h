#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// WiFi Defaults
// These are used ONLY as static fallbacks during development/flashing.
// In normal use the device provisions Wi-Fi at first boot via SoftAP
// (SSID "IoT-Setup-XXXX", http://192.168.4.1) and stores credentials in NVS.
#define WIFI_SSID ""
#define WIFI_PASSWORD ""
#define WIFI_TIMEOUT_MS 20000

// SoftAP provisioning settings
#define PROVISION_ENABLED 1                 // enable first-boot / fallback AP config
#define PROVISION_AP_PASSWORD ""            // optional AP password (empty = open)
#define PROVISION_TIMEOUT_MS 300000         // 5 min, then restart and retry STA

// MQTT Configuration (broker on the IoT VPS)
// MQTT_ENABLED_DEFAULT is the default state at first boot; a runtime
// NVS flag ("mqtt_en") can override it (commands mqtt_enable/mqtt_disable).
#define MQTT_ENABLED_DEFAULT 1
#define MQTT_BROKER "2.26.98.234"
#define MQTT_PORT 1883
#define MQTT_USER "main"
#define MQTT_PASSWORD "REDACTED"
#define MQTT_CLIENT_ID "esp32c3_main"
#define MQTT_TOPIC_PREFIX "iot"
#define MQTT_BUFFER_SIZE 2048

// Over-the-Air firmware updates (pulled over HTTPS from the public site)
#define FIRMWARE_VERSION "1.1.0"
#define OTA_FW_HOST "spe4naz.online"
#define OTA_FW_PORT 443
#define OTA_FW_PATH "/fw/main.bin"

// Web Server Configuration
#define HTTP_PORT 80
#define WEBSOCKET_PORT 81
#define API_PREFIX "/api/v1"
#define NTP_SERVER "pool.ntp.org"
#define NTP_OFFSET_SEC 0      // UTC+0 default; set to 10800 for MSK
#define NTP_UPDATE_INTERVAL_MS 3600000

// Signaling Server (device registry only — no sensor data)
// Reached over HTTPS through the public site (nginx). Bind token for the API.
#define SIGNALING_URL "https://spe4naz.online"
#define SIGNALING_TOKEN "REDACTED"
#define SIGNALING_HEARTBEAT_MS 30000

// Device Configuration
#define DEVICE_ID "esp32c3_001"
#define DEVICE_NAME "Main Controller"
#define DEVICE_TYPE "esp32c3"

// I2C Configuration
#define I2C_SDA 6
#define I2C_SCL 7
#define I2C_FREQUENCY 100000

// UART Configuration (for ESP32-C6 modules)
#define UART_RX 4
#define UART_TX 5
#define UART_BAUD_RATE 115200
#define UART_BUFFER_SIZE 1024

// SD Card Configuration
#define SD_CS 10

// Sensor Configuration
#define SENSOR_READ_INTERVAL_MS 5000
#define BME680_I2C_ADDRESS 0x76
#define BH1750_I2C_ADDRESS 0x23

// Timing
#define HEARTBEAT_INTERVAL_MS 30000
#define RECONNECT_INTERVAL_MS 5000

// Watchdog (feeds in loop(); reboots if the system hangs)
#define WDT_TIMEOUT_SECONDS 20

// SD log retention: keep at most N daily files, free space guard at P%
#define SD_MAX_LOG_FILES 60
#define SD_FULL_PERCENT 90

#endif
