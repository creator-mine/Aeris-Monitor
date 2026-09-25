#include "serial_cmd.h"
#include "config.h"
#include "ring_logger.h"
#include "wifi_config.h"
#include "mqtt_config.h"
#include "ota_updater.h"
#include "modules/sensor_registry.h"
#include "time_util.h"
#include <WiFi.h>
#include <ArduinoJson.h>
#include <esp_system.h>

// Line buffer for incoming Serial data.
static char cmdBuf[256];
static uint16_t cmdIdx = 0;

// Respond with a JSON line prefixed by >> so the Flutter app can filter it.
static void respond(const char* json) {
    Serial.print(">>");
    Serial.println(json);
}

static const char* resetReasonStr() {
    switch (esp_reset_reason()) {
        case ESP_RST_POWERON:   return "power on";
        case ESP_RST_EXT:       return "external pin";
        case ESP_RST_SW:        return "software reset / restart";
        case ESP_RST_PANIC:     return "panic / crash";
        case ESP_RST_INT_WDT:   return "interrupt watchdog";
        case ESP_RST_TASK_WDT:  return "task watchdog";
        case ESP_RST_WDT:       return "other watchdog";
        case ESP_RST_DEEPSLEEP: return "deep sleep wake";
        case ESP_RST_BROWNOUT:  return "brownout";
        case ESP_RST_SDIO:      return "sdio";
        default:                return "unknown";
    }
}

// --- command handlers ---

static void cmdStatus() {
    String json = "{";
    json += "\"type\":\"status\",";
    json += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
    json += "\"device_name\":\"" + String(DEVICE_NAME) + "\",";
    json += "\"device_type\":\"" + String(DEVICE_TYPE) + "\",";
    json += "\"uptime\":" + String(millis() / 1000) + ",";
    json += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
    json += "\"wifi_connected\":" + String(WiFi.status() == WL_CONNECTED ? "true" : "false") + ",";
    json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
    json += "\"time_synced\":" + String(timeSynced() ? "true" : "false") + ",";
    json += "\"firmware\":\"" + String(FIRMWARE_VERSION) + "\",";
    json += "\"mqtt_enabled\":" + String(MqttConfig::enabled() ? "true" : "false");
    json += "}";
    respond(json.c_str());
}

static void cmdLogs() {
    String json = "{\"type\":\"logs\",\"data\":";
    json += RingLogger::toJson(40);
    json += "}";
    respond(json.c_str());
}

static void cmdSensors() {
    String json = "{\"type\":\"sensors\",\"data\":";
    json += SensorRegistry::instance().sensorsToJson();
    json += "}";
    respond(json.c_str());
}

static void cmdModules() {
    String json = "{\"type\":\"modules\",\"data\":";
    json += SensorRegistry::instance().modulesToJson();
    json += "}";
    respond(json.c_str());
}

static void cmdInfo() {
    String json = "{";
    json += "\"type\":\"info\",";
    json += "\"firmware\":\"" + String(FIRMWARE_VERSION) + "\",";
    json += "\"chip\":\"" + String(ESP.getChipModel()) + "\",";
    json += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
    json += "\"device_name\":\"" + String(DEVICE_NAME) + "\",";
    json += "\"device_type\":\"" + String(DEVICE_TYPE) + "\",";
    json += "\"uptime\":" + String(millis() / 1000) + ",";
    json += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
    if (psramFound()) {
        json += "\"psram_size\":" + String(ESP.getPsramSize()) + ",";
    }
    json += "\"flash_size\":" + String(ESP.getFlashChipSize()) + ",";
    json += "\"sketch_size\":" + String(ESP.getSketchSize()) + ",";
    json += "\"reset_reason\":\"" + String(resetReasonStr()) + "\",";
    json += "\"wifi_ssid\":\"" + String(WiFi.SSID()) + "\",";
    json += "\"mqtt_enabled\":" + String(MqttConfig::enabled() ? "true" : "false");
    json += "}";
    respond(json.c_str());
}

static void cmdWifiSet(const char* ssid, const char* password) {
    if (!ssid || strlen(ssid) == 0) {
        respond("{\"type\":\"error\",\"error\":\"missing_ssid\"}");
        return;
    }
    if (WifiConfig::save(ssid, password ? password : "")) {
        LOG_INFO("WiFi", "Serial saved credentials (ssid=%s)", ssid);
        respond("{\"type\":\"ack\",\"command\":\"wifi_set\"}");
        delay(300);
        RingLogger::save();
        ESP.restart();
    } else {
        respond("{\"type\":\"error\",\"error\":\"nvs_write_failed\"}");
    }
}

static void cmdWifiClear() {
    WifiConfig::clear();
    LOG_INFO("WiFi", "Credentials cleared by serial command");
    respond("{\"type\":\"ack\",\"command\":\"wifi_clear\"}");
    delay(300);
    RingLogger::save();
    ESP.restart();
}

static void cmdMqttEnable(bool on) {
    MqttConfig::setEnabled(on);
    LOG_INFO("MQTT", "%s by serial command", on ? "enabled" : "disabled");
    String json = "{\"type\":\"ack\",\"command\":\"";
    json += on ? "mqtt_enable" : "mqtt_disable";
    json += "\",\"mqtt_enabled\":";
    json += on ? "true" : "false";
    json += "}";
    respond(json.c_str());
}

static void cmdRestart() {
    respond("{\"type\":\"ack\",\"command\":\"restart\"}");
    delay(300);
    RingLogger::save();
    ESP.restart();
}

static void cmdOta(const char* arg) {
    bool force = (arg != nullptr) && (strstr(arg, "force") != nullptr);
    if (OtaUpdater::request(force)) {
        respond("{\"type\":\"ack\",\"command\":\"ota\",\"status\":\"started\"}");
    } else {
        respond("{\"type\":\"error\",\"error\":\"ota_busy\"}");
    }
}

// --- parser ---

static void processCmd(const char* line) {
    // expected format: CMD:command[:arg1[:arg2...]]
    if (strncmp(line, "CMD:", 4) != 0) return;
    const char* p = line + 4;

    if (strncmp(p, "status", 6) == 0) { cmdStatus(); }
    else if (strncmp(p, "logs", 4) == 0) { cmdLogs(); }
    else if (strncmp(p, "sensors", 7) == 0) { cmdSensors(); }
    else if (strncmp(p, "modules", 7) == 0) { cmdModules(); }
    else if (strncmp(p, "info", 4) == 0) { cmdInfo(); }
    else if (strncmp(p, "wifi_set:", 9) == 0) {
        // CMD:wifi_set:ssid:password
        const char* ssid = p + 9;
        const char* colon = strchr(ssid, ':');
        if (!colon) {
            // No password field — open network
            cmdWifiSet(ssid, "");
        } else {
            // Build a temp copy to split
            char ssidBuf[64];
            size_t ssidLen = colon - ssid;
            if (ssidLen >= sizeof(ssidBuf)) ssidLen = sizeof(ssidBuf) - 1;
            memcpy(ssidBuf, ssid, ssidLen);
            ssidBuf[ssidLen] = '\0';
            cmdWifiSet(ssidBuf, colon + 1);
        }
    }
    else if (strncmp(p, "wifi_clear", 10) == 0) { cmdWifiClear(); }
    else if (strncmp(p, "mqtt_enable", 11) == 0) { cmdMqttEnable(true); }
    else if (strncmp(p, "mqtt_disable", 12) == 0) { cmdMqttEnable(false); }
    else if (strncmp(p, "ota", 3) == 0) { cmdOta(p + 3); }
    else if (strncmp(p, "restart", 7) == 0) { cmdRestart(); }
    else {
        respond("{\"type\":\"error\",\"error\":\"unknown_command\"}");
    }
}

// --- public API ---

void serialCmdInit() {
    cmdIdx = 0;
}

void serialCmdUpdate() {
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\n' || c == '\r') {
            if (cmdIdx > 0) {
                cmdBuf[cmdIdx] = '\0';
                processCmd(cmdBuf);
                cmdIdx = 0;
            }
        } else {
            if (cmdIdx < sizeof(cmdBuf) - 1) {
                cmdBuf[cmdIdx++] = c;
            }
        }
    }
}
