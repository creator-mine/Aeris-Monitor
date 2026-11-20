#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <ArduinoJson.h>
#include "config.h"
#include "time_util.h"
#include "web_server.h"
#include "lan_discovery.h"
#include "signaling_client.h"
#include "wifi_config.h"
#include "wifi_profiles.h"
#include "wifi_manager.h"
#include "provisioning.h"
#include "mqtt_config.h"
#include "device_secrets.h"
#include "relay_control.h"
#include "root_ca.h"
#include "ota_updater.h"
#include "ring_logger.h"
#include "serial_cmd.h"
#include "sys_info.h"
#include "status_led.h"
#include "esp_task_wdt.h"
#include <time.h>
#include <cmath>
#include "sensor_registry.h"

// ===================== GLOBAL STATE =====================

WiFiClientSecure wifiClient;  // MQTT over TLS (port 8883)
PubSubClient mqtt(wifiClient);

unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastReconnect = 0;

String deviceId = DEVICE_ID;

// MQTT is optional: NVS flag "mqtt_en" (default MQTT_ENABLED_DEFAULT).
bool mqttReady() {
    return MqttConfig::enabled() && mqtt.connected();
}

// ===================== STATUS LED =====================

static unsigned long wifiDownSince = 0;

// Derive the LED state from the live network/MQTT state on every loop pass.
// Explicit states set during setup (boot, provisioning, OTA) stay until this
// takes over.
void statusLedSync() {
    if (OtaUpdater::pending()) {
        StatusLed::setState(StatusLedState::Ota);
        return;
    }

    if (WiFi.status() != WL_CONNECTED) {
        if (wifiDownSince == 0) wifiDownSince = millis();
        // Blue while the first attempt is still inside its timeout, red once
        // the link has been down long enough to be a real failure.
        if (millis() - wifiDownSince > WIFI_TIMEOUT_MS) {
            StatusLed::setState(StatusLedState::Error);
        } else {
            StatusLed::setState(StatusLedState::WifiConnecting);
        }
        return;
    }

    wifiDownSince = 0;
    if (MqttConfig::enabled() && !mqtt.connected()) {
        StatusLed::setState(StatusLedState::MqttConnecting);
    } else {
        StatusLed::setState(StatusLedState::Online);
    }
}

// ===================== WIFI =====================

// Enters SoftAP provisioning only when the device has no saved networks.
// Existing profiles are never erased on a transient connection failure.
void wifiConnect() {
    if (WifiManager::begin()) return;

    if (WifiProfiles::count() == 0) {
#if PROVISION_ENABLED
        Serial.println("[WiFi] No saved networks, starting config mode");
        Provisioning::startAndWait();
        Serial.println("[WiFi] Provisioning session ended, rebooting");
        RingLogger::save();
        delay(300);
        ESP.restart();
#else
        Serial.println("[WiFi] Provisioning disabled, continuing without Wi-Fi");
#endif
    } else {
        Serial.println("[WiFi] Saved networks unavailable, retrying in background");
    }
}

void wifiUpdate() {
    WifiManager::update();
}

void wifiReconfigure() {
    Serial.println("[WiFi] Reconfiguration requested, entering config mode");
    RingLogger::save();
    // Keep the saved profiles so a cancelled or failed setup does not strand
    // the device without Wi-Fi.
    bool configured = Provisioning::startAndWait();
    Serial.println(configured ? "[WiFi] New credentials saved, rebooting"
                              : "[WiFi] Reconfiguration cancelled, rebooting");
    RingLogger::save();
    delay(300);
    ESP.restart();
}

// ===================== WATCHDOG =====================

void watchdogInit() {
#if ESP_IDF_VERSION_MAJOR >= 5
    esp_task_wdt_config_t wdtConfig = {};
    wdtConfig.timeout_ms = (uint32_t)WDT_TIMEOUT_SECONDS * 1000;
    wdtConfig.idle_core_mask = (1 << CONFIG_FREERTOS_NUMBER_OF_CORES) - 1;
    wdtConfig.trigger_panic = true;
    esp_err_t err = esp_task_wdt_init(&wdtConfig); // panic+reboot on timeout
    if (err != ESP_OK) {
        // arduino core 3.x / IDF already initialized the TWDT; subscribe to it.
        Serial.printf("[WDT] TWDT already active (%d), subscribing\n", (int)err);
    }
    err = esp_task_wdt_add(NULL); // feed loop() task explicitly
    if (err == ESP_OK) {
        Serial.printf("[WDT] Task watchdog enabled (%ds)\n", WDT_TIMEOUT_SECONDS);
    } else {
        Serial.printf("[WDT] Task watchdog add failed (%d, continuing)\n", (int)err);
    }
#else
    esp_err_t err = esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true); // panic+reboot on timeout
    if (err == ESP_OK) {
        esp_task_wdt_add(NULL); // feed loop() task explicitly
        Serial.printf("[WDT] Task watchdog enabled (%ds)\n", WDT_TIMEOUT_SECONDS);
    } else {
        Serial.println("[WDT] Task watchdog init failed (continuing)");
    }
#endif
}

// ===================== MQTT =====================

String mqttTopic(const char* suffix) {
    return String(MQTT_TOPIC_PREFIX) + "/" + deviceId + "/" + suffix;
}

void mqttPublishMetric(const char* sensorType, float value, const char* unit) {
    if (!mqttReady()) return;
    String topic = mqttTopic("sensors/") + sensorType;
    String payload = "{";
    payload += "\"device_id\":\"" + deviceId + "\",";
    payload += "\"sensor\":\"" + String(sensorType) + "\",";
    payload += "\"timestamp\":" + String((uint64_t)epochMillis()) + ",";
    payload += "\"value\":" + String(value, 2) + ",";
    payload += "\"unit\":\"" + String(unit) + "\"";
    payload += "}";
    mqtt.publish(topic.c_str(), payload.c_str());
}

void mqttPublishStatus() {
    if (!mqttReady()) return;
    String topic = mqttTopic("status");
    String payload = "{";
    payload += "\"device_id\":\"" + deviceId + "\",";
    payload += "\"device_type\":\"" + String(DEVICE_TYPE) + "\",";
    payload += "\"status\":\"online\",";
    payload += "\"uptime\":" + String(millis() / 1000) + ",";
    payload += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
    payload += "\"wifi_ssid\":\"" + WiFi.SSID() + "\",";
    payload += "\"wifi_profiles\":" + String((unsigned)WifiProfiles::count()) + ",";
    payload += "\"rssi\":" + String(WiFi.status() == WL_CONNECTED ? (int)WiFi.RSSI() : 0) + ",";
    float chipTemp = chipTemperatureCelsius();
    if (!std::isnan(chipTemp)) {
        payload += "\"chip_temp\":" + String(chipTemp, 1) + ",";
    }

    if (RelayControl::enabled()) {
        payload += "\"relay\":" + String(RelayControl::state() ? "true" : "false") + ",";
    }

    auto modules = SensorRegistry::instance().activeModules();
    payload += "\"modules\":[";
    for (size_t i = 0; i < modules.size(); i++) {
        if (i > 0) payload += ",";
        payload += "\"" + String(modules[i]->moduleName()) + "\"";
    }
    payload += "]}";
    mqtt.publish(topic.c_str(), payload.c_str());
}

void mqttPublishRelay() {
    if (!mqttReady()) return;
    String topic = mqttTopic("relay");
    String payload = RelayControl::toJson();
    mqtt.publish(topic.c_str(), payload.c_str());
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
    if (length > 512) {
        Serial.printf("[MQTT] Oversized message (%u bytes) dropped\n", length);
        return;
    }

    String msg;
    for (unsigned int i = 0; i < length; i++) {
        msg += (char)payload[i];
    }
    Serial.println("[MQTT] Received: " + msg);

    if (msg.indexOf("wifi_list") >= 0) {
        JsonDocument doc;
        String requestId;
        if (!deserializeJson(doc, msg)) {
            requestId = String((const char*)(doc["request_id"] | ""));
        }
        String payload = "{\"request_id\":\"" + requestId +
                         "\",\"status\":\"list\",\"data\":" +
                         WifiManager::statusJson() + "}";
        mqtt.publish(mqttTopic("wifi/result").c_str(), payload.c_str());
        return;
    }

    if (msg.indexOf("wifi_prepare") >= 0) {
        String response = WifiManager::handleRemotePrepare(msg);
        mqtt.publish(mqttTopic("wifi/result").c_str(), response.c_str());
        return;
    }

    if (msg.indexOf("wifi_commit") >= 0) {
        String response = WifiManager::handleRemoteCommit(msg);
        mqtt.publish(mqttTopic("wifi/result").c_str(), response.c_str());
        return;
    }

    if (msg.indexOf("wifi_set") >= 0) {
        JsonDocument doc;
        if (!deserializeJson(doc, msg)) {
            const char* ssid = doc["ssid"];
            const char* password = doc["password"];
            if (ssid && strlen(ssid) > 0) {
                if (WifiConfig::save(ssid, password ? password : "")) {
                    LOG_INFO("WiFi", "MQTT saved credentials (ssid=%s), reconnecting", ssid);
                    RingLogger::save();
                    ESP.restart();
                }
            }
        }
        return;
    }

    // Relay / actuator: JSON {"command":"relay","state":"on"} / {"relay":true}
    // or the plain text form "relay:on" used by server rules.
    {
        JsonDocument doc;
        bool handled = false;
        if (!deserializeJson(doc, msg)) {
            const char* cmd = doc["command"] | "";
            const char* st = doc["state"] | "";
            if (RelayControl::handleCommand(cmd, st)) {
                handled = true;
            } else if (doc["relay"].is<bool>()) {
                RelayControl::set(doc["relay"].as<bool>());
                handled = true;
            }
        }
        if (!handled) {
            int idx = msg.indexOf("relay:");
            if (idx >= 0) {
                String st = msg.substring(idx + 6);
                st.trim();
                handled = RelayControl::handleCommand("relay", st.c_str());
            }
        }
        if (handled) {
            mqttPublishRelay();
            return;
        }
    }

    if (msg.indexOf("restart") >= 0) {
        RingLogger::save();
        ESP.restart();
    }
    if (msg.indexOf("rollback") >= 0) {
        OtaUpdater::rollback();
        return;
    }
    if (msg.indexOf("ota") >= 0) {
        bool force = msg.indexOf("force") >= 0;
        if (OtaUpdater::request(force)) {
            Serial.println("[MQTT] OTA request accepted");
        } else {
            Serial.println("[MQTT] OTA already pending, request ignored");
        }
    }
    if (msg.indexOf("read_sensor") >= 0) {
        SensorRegistry::instance().forceRead();
        lastSensorRead = 0;
    }
    if (msg.indexOf("rescan") >= 0) {
        SensorRegistry::instance().scanI2CBus(I2C_SDA, I2C_SCL);
    }
    if (msg.indexOf("wifi_reconfigure") >= 0) {
        wifiReconfigure();
    }
}

void mqttConnect() {
    if (mqtt.connected()) return;
    if (!MqttConfig::enabled()) {
        Serial.println("[MQTT] Disabled by config");
        return;
    }
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[MQTT] Skipped (no Wi-Fi)");  // lwIP not usable without a link
        return;
    }

    String clientId = String(MQTT_CLIENT_ID) + "_" + String(random(1000));
    String user = DeviceSecrets::mqttUser();
    String pass = DeviceSecrets::mqttPassword();
    if (user.isEmpty() || pass.isEmpty()) {
        Serial.println("[MQTT] Skipped (no credentials provisioned)");
        return;
    }
    Serial.print("[MQTT] Connecting (TLS)...");
    wifiClient.setCACert(ROOT_CA_CERT);

    if (mqtt.connect(clientId.c_str(), user.c_str(), pass.c_str())) {
        Serial.println(" OK");
        LOG_INFO("MQTT", "Connected to %s:%d", MQTT_BROKER, MQTT_PORT);
        String cmdTopic = mqttTopic("commands");
        mqtt.subscribe(cmdTopic.c_str());
        Serial.println("[MQTT] Subscribed: " + cmdTopic);
        mqttPublishStatus();
    } else {
        Serial.println(" FAIL rc=" + String(mqtt.state()));
        LOG_INFO("MQTT", "Connect failed rc=%d", mqtt.state());
    }
}

void mqttUpdate() {
    static bool wasConnected = true;
    if (!MqttConfig::enabled()) {
        if (mqtt.connected()) {
            Serial.println("[MQTT] Disabled, disconnecting");
            mqtt.disconnect();
            mqtt.loop();
        }
        return;
    }
    if (!mqtt.connected()) {
        if (wasConnected) {
            LOG_INFO("MQTT", "Connection lost, reconnecting...");
            wasConnected = false;
        }
        if (millis() - lastReconnect > RECONNECT_INTERVAL_MS) {
            lastReconnect = millis();
            mqttConnect();
        }
    } else {
        if (!wasConnected) {
            LOG_INFO("MQTT", "Reconnected");
            wasConnected = true;
        }
        mqtt.loop();
    }
}

// ===================== UART BRIDGE =====================

#include "uart_protocol.h"
#include <uart_frame.h>

// Resync-aware frame parser: survives partial/corrupt frames by dropping one
// byte at a time until a valid 0xAA 0x55 header + CRC frame is found.
UartFrameParser uartFrame;

// Registered remote modules: one moduleId -> one or more sensors, each with its
// own metric keys. The UART module registers ALL its sensors in one frame and
// sends sensor data as one value stream (flattened across sensors in the same
// order), so values map positionally onto the flattened metric list.
// A UART module reports every sensor it hosts in one registration frame, so the
// flattened metric limit has to cover the whole module, not one sensor: five
// drivers (BME680, BH1750, SCD30, INA219, BMP280) already contribute 13.
#define REMOTE_MODULE_MAX_SENSORS 8
#define REMOTE_MODULE_MAX_METRICS 24
#define REMOTE_MODULE_MAX_VALUE_BYTES (REMOTE_MODULE_MAX_METRICS * 4)
#define REMOTE_MODULE_COUNT 8
#define REMOTE_METRIC_KEY_LEN 23
#define REMOTE_METRIC_UNIT_LEN 7

struct RemoteSensor {
    uint8_t typeId;
    char name[32];
    uint8_t metricCount;   // metrics contributed by this sensor
    uint8_t metricOffset;  // index into module's flattened metric list
};

struct RemoteModule {
    uint8_t moduleId;
    RemoteSensor sensors[REMOTE_MODULE_MAX_SENSORS];
    uint8_t sensorCount;
    char metricKeys[REMOTE_MODULE_MAX_METRICS][REMOTE_METRIC_KEY_LEN + 1];
    char metricUnits[REMOTE_MODULE_MAX_METRICS][REMOTE_METRIC_UNIT_LEN + 1];
    uint8_t metricCount;  // total metrics across all sensors
    uint8_t values[REMOTE_MODULE_MAX_VALUE_BYTES]; // last received raw floats
    uint8_t valueCount;
    bool hasData;
};

RemoteModule remoteModules[REMOTE_MODULE_COUNT];
uint8_t remoteModuleCount = 0;

RemoteModule* findRemoteModule(uint8_t moduleId) {
    for (uint8_t i = 0; i < remoteModuleCount; i++) {
        if (remoteModules[i].moduleId == moduleId) return &remoteModules[i];
    }
    return nullptr;
}

RemoteModule* findOrCreateRemoteModule(uint8_t moduleId) {
    RemoteModule* mod = findRemoteModule(moduleId);
    if (mod != nullptr) return mod;
    if (remoteModuleCount >= REMOTE_MODULE_COUNT) return nullptr;

    mod = &remoteModules[remoteModuleCount++];
    memset(mod, 0, sizeof(RemoteModule));
    mod->moduleId = moduleId;
    return mod;
}

// Parses a CMD_REGISTER payload into mod. Returns false and leaves mod cleared
// when the frame is malformed: a half-filled registration would map data values
// onto the wrong keys, which is worse than no registration at all.
// len is uint16_t on purpose: the frame header carries a 16-bit length and a
// registration with the five current drivers is already ~255 bytes.
static bool parseRegisterFrame(RemoteModule* mod, uint8_t* payload, uint16_t len,
                               uint16_t* droppedOut) {
    memset(mod, 0, sizeof(RemoteModule));

    uint16_t idx = 0;
    if (idx >= len) return false;

    uint8_t sensorCount = payload[idx++];
    mod->sensorCount =
        sensorCount > REMOTE_MODULE_MAX_SENSORS ? REMOTE_MODULE_MAX_SENSORS
                                                : sensorCount;
    uint16_t dropped = 0;

    for (uint8_t s = 0; s < mod->sensorCount; s++) {
        RemoteSensor& sensor = mod->sensors[s];

        if (idx + 2 > len) return false;
        sensor.typeId = payload[idx++];

        uint8_t nameLen = payload[idx++];
        if (idx + nameLen > len || nameLen > 31) return false;
        memcpy(sensor.name, payload + idx, nameLen);
        sensor.name[nameLen] = '\0';
        idx += nameLen;

        if (idx >= len) return false;
        uint8_t metricCount = payload[idx++];
        if (metricCount > REMOTE_MODULE_MAX_METRICS)
            metricCount = REMOTE_MODULE_MAX_METRICS;
        sensor.metricOffset = mod->metricCount;

        for (uint8_t m = 0; m < metricCount; m++) {
            // Every length is validated against the buffer before it is used:
            // a corrupt length byte would otherwise overflow the fixed-size key
            // and unit arrays below.
            if (idx + 2 > len) return false;
            uint8_t keyLen = payload[idx];
            if (idx + 1 + keyLen >= len) return false;
            uint8_t unitLen = payload[idx + 1 + keyLen];
            if (idx + 2 + keyLen + unitLen > len) return false;
            if (keyLen > REMOTE_METRIC_KEY_LEN ||
                unitLen > REMOTE_METRIC_UNIT_LEN)
                return false;

            if (mod->metricCount >= REMOTE_MODULE_MAX_METRICS) {
                // Over the module limit: skip the descriptor so the sensors
                // behind it are still parsed correctly. The accepted metrics stay
                // a prefix of the module's stream, which is what keeps keys and
                // values aligned.
                dropped++;
                idx += 2 + keyLen + unitLen;
                continue;
            }

            idx++; // key length
            memcpy(mod->metricKeys[mod->metricCount], payload + idx, keyLen);
            mod->metricKeys[mod->metricCount][keyLen] = '\0';
            idx += keyLen;

            idx++; // unit length
            memcpy(mod->metricUnits[mod->metricCount], payload + idx, unitLen);
            mod->metricUnits[mod->metricCount][unitLen] = '\0';
            idx += unitLen;

            mod->metricCount++;
        }
        sensor.metricCount = mod->metricCount - sensor.metricOffset;
    }

    *droppedOut = dropped;
    return true;
}

void uartProcessRegister(uint8_t moduleId, uint8_t* payload, uint16_t len) {
    RemoteModule* mod = findOrCreateRemoteModule(moduleId);
    if (mod == nullptr) {
        Serial.println("[UART] Too many modules!");
        LOG_INFO("UART", "Too many modules!");
        return;
    }

    uint16_t dropped = 0;
    // A register frame fully describes the module, so repeated (periodic)
    // registers stay idempotent: mod is cleared at the start of the parse.
    if (!parseRegisterFrame(mod, payload, len, &dropped)) {
        memset(mod, 0, sizeof(RemoteModule));
        mod->moduleId = moduleId;
        Serial.printf("[UART] Module %d sent a malformed register frame, ignored\n",
                      moduleId);
        return;
    }
    mod->moduleId = moduleId;

    if (dropped > 0) {
        Serial.printf("[UART] Module %d: %u metric(s) dropped, module limit is %d\n",
                      moduleId, dropped, REMOTE_MODULE_MAX_METRICS);
    }

    Serial.printf("[UART] Module %d registered: %d sensor(s), %d metric(s)\n",
                  moduleId, mod->sensorCount, mod->metricCount);
    LOG_INFO("UART", "Module %d registered: %d sensor(s), %d metric(s)",
             moduleId, mod->sensorCount, mod->metricCount);
    for (uint8_t s = 0; s < mod->sensorCount; s++) {
        Serial.printf("  Sensor %s (type %d):\n",
                      mod->sensors[s].name, mod->sensors[s].typeId);
        for (uint8_t m = 0; m < mod->sensors[s].metricCount; m++) {
            uint8_t mi = mod->sensors[s].metricOffset + m;
            Serial.printf("    [%d] %s (%s)\n", mi, mod->metricKeys[mi], mod->metricUnits[mi]);
        }
    }
}

void uartProcessSensorData(uint8_t moduleId, uint8_t* payload, uint16_t len) {
    RemoteModule* mod = findRemoteModule(moduleId);
    if (mod == nullptr) {
        Serial.printf("[UART] Data from unknown module %d (not registered)\n", moduleId);
        return;
    }

    if (len < 4) return;
    uint16_t idx = 4; // skip timestamp

    mod->valueCount = 0;
    while (idx + 4 <= len && mod->valueCount < REMOTE_MODULE_MAX_METRICS) {
        memcpy(&mod->values[mod->valueCount * 4], payload + idx, 4);
        mod->valueCount++;
        idx += 4;
    }
    mod->hasData = true;

    Serial.printf("[UART] Module %d data:\n", moduleId);
    uint8_t limit = mod->metricCount < mod->valueCount ? mod->metricCount : mod->valueCount;
    for (uint8_t v = 0; v < limit; v++) {
        float value;
        memcpy(&value, &mod->values[v * 4], 4);
        // A metric without a reading yet arrives as NaN: neither MQTT nor the
        // SD log can represent it, and "nan" would break JSON consumers.
        if (!std::isfinite(value)) continue;
        Serial.printf("  %s = %.2f %s\n", mod->metricKeys[v], value, mod->metricUnits[v]);

        if (mqttReady()) {
            mqttPublishMetric(mod->metricKeys[v], value, mod->metricUnits[v]);
        }
    }
}

void uartProcessPacket(uint8_t moduleId, uint8_t cmd, uint8_t* payload,
                       uint16_t len, void* context) {
    (void)context;
    switch (cmd) {
        case CMD_REGISTER:
            uartProcessRegister(moduleId, payload, len);
            break;
        case CMD_SENSOR_DATA:
            uartProcessSensorData(moduleId, payload, len);
            break;
        case CMD_HEARTBEAT:
            Serial.printf("[UART] Heartbeat from module %d\n", moduleId);
            break;
        default:
            Serial.printf("[UART] Unknown cmd 0x%02X from module %d\n", cmd, moduleId);
            LOG_INFO("UART", "Unknown cmd 0x%02X from module %d", cmd, moduleId);
            break;
    }
}

void uartUpdate() {
    while (Serial1.available()) {
        uartFrame.feed(Serial1.read(), uartProcessPacket, nullptr);
    }
}

// ===================== SD CARD =====================

bool sdMounted = false;
unsigned long lastSdCleanup = 0;
const unsigned long SD_CLEANUP_INTERVAL_MS = 3600000; // check retention once an hour

// Rotate log files by date: /data_<device>_YYYYMMDD.csv.
// Before time sync (NTP) still working, falls back to the legacy flat file.
String sdDailyPath() {
    char buf[80];
    if (timeSynced() && time(nullptr) > 100000) {
        time_t now = time(nullptr);
        struct tm tm;
        gmtime_r(&now, &tm);
        snprintf(buf, sizeof(buf), "/data_%s_%04d%02d%02d.csv",
                 DEVICE_ID, tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday);
        return String(buf);
    }
    return String("/data_") + String(DEVICE_ID) + ".csv";
}

struct SdLogEntry {
    char name[40];
    time_t mtime;
};

int sdCollectLogs(SdLogEntry* out, int max) {
    int n = 0;
    File root = SD.open("/");
    if (!root) return 0;

    String prefix = String("data_") + String(DEVICE_ID) + "_";
    File file = root.openNextFile();
    while (file && n < max) {
        String name = String(file.name());
        if (name.startsWith(prefix) && name.endsWith(".csv")) {
            snprintf(out[n].name, sizeof(out[n].name), "%s", name.c_str());
            out[n].mtime = file.getLastWrite();
            n++;
        }
        file.close();
        file = root.openNextFile();
    }
    root.close();

    // bubble sort ascending by mtime (oldest first)
    for (int i = 0; i < n - 1; i++) {
        for (int j = i + 1; j < n; j++) {
            if (out[j].mtime < out[i].mtime) {
                SdLogEntry t = out[i];
                out[i] = out[j];
                out[j] = t;
            }
        }
    }
    return n;
}

void sdDeleteOldestLogs(int count) {
    SdLogEntry files[64];
    int n = sdCollectLogs(files, 64);
    int toDelete = n < count ? 0 : count;
    for (int i = 0; i < toDelete; i++) {
        String p = String("/") + files[i].name;
        if (SD.remove(p)) {
            Serial.printf("[SD] Removed old log %s\n", p.c_str());
        }
    }
}

void sdRotateCleanup() {
    if (!sdMounted) return;
    SdLogEntry files[64];
    int n = sdCollectLogs(files, 64);

    if (n > SD_MAX_LOG_FILES) {
        Serial.printf("[SD] %d log files, keeping last %d\n", n, SD_MAX_LOG_FILES);
        sdDeleteOldestLogs(n - SD_MAX_LOG_FILES);
    }

    uint64_t total = SD.totalBytes();
    uint64_t used = SD.usedBytes();
    if (total > 0 && used > 0 && (used * 100) / total > SD_FULL_PERCENT) {
        Serial.printf("[SD] Card at %llu%% full, trimming old logs\n", (used * 100) / total);
        sdDeleteOldestLogs(5);
    }
}

bool sdInit() {
    if (!SD.begin(SD_CS)) {
        Serial.println("[SD] Mount failed");
        LOG_INFO("SD", "Mount failed");
        return false;
    }
    Serial.print("[SD] Type: ");
    Serial.print(SD.cardType() == CARD_SDHC ? "SDHC" : SD.cardType() == CARD_SD ? "SD" : "Unknown");
    Serial.print(" Size: ");
    Serial.print(SD.totalBytes() / (1024 * 1024));
    Serial.println(" MB");
    sdMounted = true;
    LOG_INFO("SD", "Mounted, %llu MB total", SD.totalBytes() / (1024 * 1024));
    return true;
}

void sdSave(const char* sensorType, float value, const char* unit) {
    if (!sdMounted) return;
    String path = sdDailyPath();
    File f = SD.open(path, FILE_APPEND);
    if (f) {
        f.print(epochMillis());
        f.print(",");
        f.print(sensorType);
        f.print(",");
        f.print(value, 2);
        f.print(",");
        f.println(unit);
        f.close();
    }
}

// ===================== SENSORS (MODULE SYSTEM) =====================

// Publishing every metric on every cycle floods MQTT and the SD log as soon as
// more sensors are added, so a value is published when it changes and at least
// once per METRIC_HEARTBEAT_MS to keep the topic alive.
#define METRIC_EPSILON 0.01F
#define METRIC_HEARTBEAT_MS 60000
#define MAX_TRACKED_METRICS 48

struct TrackedMetric {
    char key[24];
    float value;
    unsigned long at;
};
static TrackedMetric trackedMetrics[MAX_TRACKED_METRICS];
static size_t trackedMetricCount = 0;

static bool metricShouldPublish(const char* key, float value) {
    unsigned long now = millis();
    for (size_t i = 0; i < trackedMetricCount; i++) {
        if (strcmp(trackedMetrics[i].key, key) != 0) continue;
        bool changed = fabsf(value - trackedMetrics[i].value) > METRIC_EPSILON;
        bool stale = now - trackedMetrics[i].at >= METRIC_HEARTBEAT_MS;
        trackedMetrics[i].value = value;
        trackedMetrics[i].at = now;
        return changed || stale;
    }

    if (trackedMetricCount < MAX_TRACKED_METRICS) {
        TrackedMetric& slot = trackedMetrics[trackedMetricCount++];
        snprintf(slot.key, sizeof(slot.key), "%s", key);
        slot.value = value;
        slot.at = now;
    }
    return true;
}

void sensorsInit() {
    SensorRegistry& registry = SensorRegistry::instance();

    // Drivers register themselves: REGISTER_SENSOR at the end of each driver
    // .cpp, so adding a sensor never touches this function.
    static const uint8_t kMuxAddresses[] = I2C_MUX_ADDRESSES;
    registry.setMuxAddresses(kMuxAddresses,
                             sizeof(kMuxAddresses) / sizeof(kMuxAddresses[0]));

    registry.scanI2CBus(I2C_SDA, I2C_SCL);

    Serial.printf("[System] Active modules: %d\n", registry.activeCount());
    LOG_INFO("Boot", "Active modules: %d", registry.activeCount());
}

void sensorsRead() {
    auto records = SensorRegistry::instance().activeRecords();

    for (auto& rec : records) {
        for (auto& m : rec.cached) {
            // Skip metrics without a valid reading (SCD30 warm-up, failed read):
            // MQTT and the CSV log have no representation for NaN.
            if (!std::isfinite(m.value)) continue;
            if (!metricShouldPublish(m.key, m.value)) continue;
            if (mqttReady()) {
                mqttPublishMetric(m.key, m.value, m.unit);
            }
            sdSave(m.key, m.value, m.unit);
        }
    }
}

// ===================== SETUP / LOOP =====================

static bool g_webStarted = false;

// The device may boot without Wi-Fi and connect later. Start the HTTP server
// and LAN discovery as soon as a link is available.
void startWebIfConnected() {
    if (g_webStarted || WiFi.status() != WL_CONNECTED) return;
    WebServer::instance().begin(HTTP_PORT, WEBSOCKET_PORT);
    LanDiscovery::begin();
    g_webStarted = true;
}

void setup() {
    Serial.begin(115200);
#if defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
    // Do not stall the firmware when no USB host is attached.
    Serial.setTxTimeoutMs(50);
#endif
    StatusLed::begin();
    delay(1000);
    StatusLed::update();  // finish the boot flash

    RingLogger::init();   // restore persisted logs (survive reboot history)

    MqttConfig::init();   // cache NVS "mqtt_en" flag in RAM (avoids NVS per loop)
    DeviceSecrets::init();  // load/migrate MQTT + signaling credentials from NVS
    RelayControl::init();   // safe default: output off

    Serial.println("=================================");
    Serial.print  ("  Aeris Monitor - ");
    Serial.println(ESP.getChipModel());
    Serial.println("  Device: " + deviceId);
    Serial.println("=================================");

    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX, UART_TX);
    LOG_INFO("Boot", "Firmware %s starting (chip %d MHz, %d MB flash)",
             FIRMWARE_VERSION, ESP.getCpuFreqMHz(), ESP.getFlashChipSize() / (1024 * 1024));

    StatusLed::setState(StatusLedState::WifiConnecting);
    wifiConnect();
    ntpInit();

    if (MqttConfig::enabled()) {
        StatusLed::setState(StatusLedState::MqttConnecting);
        mqtt.setServer(MQTT_BROKER, MQTT_PORT);
        mqtt.setBufferSize(MQTT_BUFFER_SIZE);
        wifiClient.setCACert(ROOT_CA_CERT);  // ISRG Root X1 (Let's Encrypt)
        mqtt.setCallback(mqttCallback);
        mqttConnect();
    } else {
        Serial.println("[MQTT] Skipping MQTT setup (disabled)");
        StatusLed::setState(StatusLedState::Online);
    }

    sdInit();
    sensorsInit();

    startWebIfConnected();
    signalingInit();

    // Subscribe loop only after the long boot sequence (Wi-Fi attempts, SD,
    // sensor probing) has finished.
    watchdogInit();

    LOG_INFO("Boot", "Firmware %s ready", FIRMWARE_VERSION);
    serialCmdInit();
    Serial.println("=================================");
    Serial.printf("  Ready! Free heap: %d\n", ESP.getFreeHeap());
    Serial.println("=================================");
}

void loop() {
    esp_task_wdt_reset(); // feed watchdog each iteration

    if (OtaUpdater::pending()) {
        StatusLed::setState(StatusLedState::Ota);
        StatusLed::update();
        OtaUpdater::apply();
    }

    if (millis() - lastSdCleanup >= SD_CLEANUP_INTERVAL_MS) {
        lastSdCleanup = millis();
        sdRotateCleanup();
    }

    statusLedSync();
    wifiUpdate();
    startWebIfConnected();
    LanDiscovery::update();
    mqttUpdate();
    if (mqttReady()) {
        String wifiEvent = WifiManager::takeEvent();
        if (!wifiEvent.isEmpty()) {
            mqtt.publish(mqttTopic("wifi/result").c_str(), wifiEvent.c_str());
        }
    }
    uartUpdate();
    ntpEnsureSynced();
    serialCmdUpdate();

    WebServer::instance().update();
    SensorRegistry::instance().checkLiveness();
    SensorRegistry::instance().poll();
    signalingUpdate();

    if (millis() - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
        lastSensorRead = millis();
        sensorsRead();
        WebServer::instance().broadcastSensors();
    }

    if (millis() - lastHeartbeat >= HEARTBEAT_INTERVAL_MS) {
        lastHeartbeat = millis();
        if (mqttReady()) {
            mqttPublishStatus();
        }
        WebServer::instance().broadcastStatus();
    }

    StatusLed::update();
    delay(10);
}
