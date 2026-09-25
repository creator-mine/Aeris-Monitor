#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ============================================================
// Board configuration.
//
// All settings below are board defaults (ESP32-C3 main controller).
// Every define is guarded with #ifndef so a specific PlatformIO env
// can override it via build_flags (see platformio.ini [env:*]).
//
// Supported boards:
//   [env:esp32-c3]  ESP32-C3 (LOLIN C3 mini) main controller
//   [env:esp32-s3]  ESP32-S3 N16R8 (16 MB flash / 8 MB PSRAM) controller
// ============================================================

// WiFi Defaults
// These are used ONLY as static fallbacks during development/flashing.
// In normal use the device provisions Wi-Fi at first boot via SoftAP
// (SSID "IoT-Setup-XXXX", http://192.168.4.1) and stores credentials in NVS.
#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif
#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD ""
#endif
#ifndef WIFI_TIMEOUT_MS
#define WIFI_TIMEOUT_MS 20000
#endif

// SoftAP provisioning settings
#ifndef PROVISION_ENABLED
#define PROVISION_ENABLED 1                // enable first-boot / fallback AP config
#endif
#ifndef PROVISION_AP_PASSWORD
#define PROVISION_AP_PASSWORD ""           // optional AP password (empty = open)
#endif
#ifndef PROVISION_TIMEOUT_MS
#define PROVISION_TIMEOUT_MS 300000        // 5 min, then restart and retry STA
#endif

// MQTT Configuration (broker on the IoT VPS)
// MQTT_ENABLED_DEFAULT is the default state at first boot; a runtime
// NVS flag ("mqtt_en") can override it (commands mqtt_enable/mqtt_disable).
#ifndef MQTT_ENABLED_DEFAULT
#define MQTT_ENABLED_DEFAULT 1
#endif
#ifndef MQTT_BROKER
#define MQTT_BROKER "2.26.98.234"
#endif
#ifndef MQTT_PORT
#define MQTT_PORT 1883
#endif
#ifndef MQTT_USER
#define MQTT_USER "main"
#endif
#ifndef MQTT_PASSWORD
#define MQTT_PASSWORD "24ebc3e8d31588d24b7c56ae1ef8a267"
#endif
#ifndef MQTT_CLIENT_ID
#define MQTT_CLIENT_ID "esp32c3_main"
#endif
#ifndef MQTT_TOPIC_PREFIX
#define MQTT_TOPIC_PREFIX "iot"
#endif
#ifndef MQTT_BUFFER_SIZE
#define MQTT_BUFFER_SIZE 2048
#endif

// Over-the-Air firmware updates (pulled over HTTPS from the public site).
// Each board pulls its own binary + manifest (per-device_type files).
#ifndef FIRMWARE_VERSION
#define FIRMWARE_VERSION "1.2.2"
#endif
#ifndef OTA_FW_HOST
#define OTA_FW_HOST "spe4naz.online"
#endif
#ifndef OTA_FW_PORT
#define OTA_FW_PORT 443
#endif
#ifndef OTA_FW_PATH
#define OTA_FW_PATH "/fw/main.bin"
#endif
#ifndef OTA_VERSION_PATH
#define OTA_VERSION_PATH "/fw/version.json"
#endif

// Web Server Configuration
#ifndef HTTP_PORT
#define HTTP_PORT 80
#endif
#ifndef WEBSOCKET_PORT
#define WEBSOCKET_PORT 81
#endif
#ifndef API_PREFIX
#define API_PREFIX "/api/v1"
#endif
#ifndef NTP_SERVER
#define NTP_SERVER "pool.ntp.org"
#endif
#ifndef NTP_OFFSET_SEC
#define NTP_OFFSET_SEC 0      // UTC+0 default; set to 10800 for MSK
#endif
#ifndef NTP_UPDATE_INTERVAL_MS
#define NTP_UPDATE_INTERVAL_MS 3600000
#endif

// Signaling Server (device registry only — no sensor data)
// Reached over HTTPS through the public site (nginx). Bind token for the API.
#ifndef SIGNALING_URL
#define SIGNALING_URL "https://spe4naz.online"
#endif
#ifndef SIGNALING_TOKEN
#define SIGNALING_TOKEN "296a5ec2b5987baec785771bed971d30158859796bf1ee04f575e6db52f710cf"
#endif
#ifndef SIGNALING_HEARTBEAT_MS
#define SIGNALING_HEARTBEAT_MS 30000
#endif

// Device Configuration
#ifndef DEVICE_ID
#define DEVICE_ID "esp32c3_001"
#endif
#ifndef DEVICE_NAME
#define DEVICE_NAME "Main Controller"
#endif
// Registry device type ("esp32c3" / "esp32s3" chip-level convention).
#ifndef DEVICE_TYPE
#define DEVICE_TYPE "esp32c3"
#endif

// I2C Configuration (ESP32-C3: SDA 6 / SCL 7)
// ESP32-S3 overrides via build_flags: SDA 8 / SCL 9.
#ifndef I2C_SDA
#define I2C_SDA 6
#endif
#ifndef I2C_SCL
#define I2C_SCL 7
#endif
#ifndef I2C_FREQUENCY
#define I2C_FREQUENCY 100000
#endif

// UART Configuration (for ESP32-C6 sensor modules)
// ESP32-S3 overrides via build_flags: RX 4 / TX 5.
#ifndef UART_RX
#define UART_RX 4
#endif
#ifndef UART_TX
#define UART_TX 5
#endif
#ifndef UART_BAUD_RATE
#define UART_BAUD_RATE 115200
#endif
#ifndef UART_BUFFER_SIZE
#define UART_BUFFER_SIZE 1024
#endif

// SD Card Configuration (chip select pin)
// ESP32-S3 overrides via build_flags: CS 10 (SPI default SCK12/MISO11/MOSI13).
#ifndef SD_CS
#define SD_CS 10
#endif

// Sensor Configuration
#ifndef SENSOR_READ_INTERVAL_MS
#define SENSOR_READ_INTERVAL_MS 5000
#endif
#ifndef BME680_I2C_ADDRESS
#define BME680_I2C_ADDRESS 0x76
#endif
#ifndef BH1750_I2C_ADDRESS
#define BH1750_I2C_ADDRESS 0x23
#endif

// Timing
#ifndef HEARTBEAT_INTERVAL_MS
#define HEARTBEAT_INTERVAL_MS 30000
#endif
#ifndef RECONNECT_INTERVAL_MS
#define RECONNECT_INTERVAL_MS 5000
#endif

// Watchdog (feeds in loop(); reboots if the system hangs)
#ifndef WDT_TIMEOUT_SECONDS
#define WDT_TIMEOUT_SECONDS 20
#endif

// SD log retention: keep at most N daily files, free space guard at P%
#ifndef SD_MAX_LOG_FILES
#define SD_MAX_LOG_FILES 60
#endif
#ifndef SD_FULL_PERCENT
#define SD_FULL_PERCENT 90
#endif

// In-memory ring buffer for device logs (exposed via /api/v1/logs)
#ifndef LOG_MAX_ENTRIES
#define LOG_MAX_ENTRIES 64
#endif

#endif