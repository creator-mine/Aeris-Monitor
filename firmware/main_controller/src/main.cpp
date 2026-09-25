#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <ArduinoJson.h>
#include "config.h"
#include "time_util.h"
#include "web_server.h"
#include "signaling_client.h"
#include "wifi_config.h"
#include "provisioning.h"
#include "mqtt_config.h"
#include "ota_updater.h"
#include "ring_logger.h"
#include "serial_cmd.h"
#include "esp_task_wdt.h"
#include <time.h>
#include "modules/sensor_registry.h"
#include <bme680_module.h>
#include <bh1750_module.h>

// ===================== GLOBAL STATE =====================

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastReconnect = 0;

String deviceId = DEVICE_ID;

// MQTT is optional: NVS flag "mqtt_en" (default MQTT_ENABLED_DEFAULT).
bool mqttReady() {
    return MqttConfig::enabled() && mqtt.connected();
}

// ===================== WIFI =====================

bool wifiConnectSta(const char* ssid, const char* password) {
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(DEVICE_ID);
    WiFi.begin(ssid, password);

    Serial.print("[WiFi] Connecting to ");
    Serial.print(ssid);
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start > WIFI_TIMEOUT_MS) {
            Serial.println(" TIMEOUT");
            return false;
        }
        delay(500);
        Serial.print(".");
        esp_task_wdt_reset(); // keep feeding even during long reconnect waits
    }
    Serial.println();
    Serial.print("[WiFi] IP: ");
    Serial.println(WiFi.localIP());
    LOG_INFO("WiFi", "Connected to %s", ssid);
    return true;
}

// Try connecting: first stored NVS credentials, then the static fallback.
// Returns true on success.
// clearOnFail should only be true at boot: wiping stored credentials on a
// transient runtime failure (router reboot, AP power-up delay) would strand
// the device offline with no way to re-provision over the air.
bool wifiTryConnect(bool clearOnFail = false) {
    char ssid[64] = "";
    char password[64] = "";

    if (WifiConfig::load(ssid, sizeof(ssid), password, sizeof(password))) {
        Serial.println("[WiFi] Using stored credentials");
        if (wifiConnectSta(ssid, password)) return true;
        Serial.println("[WiFi] Stored credentials failed");
        if (clearOnFail) WifiConfig::clear();
    }

    if (strlen(WIFI_SSID) > 0) {
        if (wifiConnectSta(WIFI_SSID, WIFI_PASSWORD)) return true;
    }

    return false;
}

// Enters SoftAP provisioning if enabled and no connection can be made.
// Only called at boot. If the provisioning session ends without a
// connection (timeout, saved-but-failed, etc.) it reboots so the device
// stays in a setup loop until usable Wi-Fi credentials are provided.
void wifiConnect() {
    if (wifiTryConnect(true)) return;

#if PROVISION_ENABLED
    Serial.println("[WiFi] No connection, starting config mode");
    Provisioning::startAndWait();
    Serial.println("[WiFi] Provisioning session ended, rebooting");
    RingLogger::save();
    delay(300);
    ESP.restart();
#else
    Serial.println("[WiFi] Provisioning disabled, continuing without Wi-Fi");
#endif
}

void wifiUpdate() {
    static bool wasConnected = true;
    if (WiFi.status() != WL_CONNECTED) {
        if (wasConnected) {
            LOG_INFO("WiFi", "Connection lost, reconnecting...");
            wasConnected = false;
        }
        if (millis() - lastReconnect > RECONNECT_INTERVAL_MS) {
            lastReconnect = millis();
            wifiTryConnect();
        }
    } else {
        if (!wasConnected) {
            LOG_INFO("WiFi", "Reconnected");
            wasConnected = true;
        }
    }
}

void wifiReconfigure() {
    Serial.println("[WiFi] Reconfiguration requested, entering config mode");
    RingLogger::save();
    WifiConfig::clear();
    bool configured = Provisioning::startAndWait();
    Serial.println(configured ? "[WiFi] New credentials saved, rebooting"
                              : "[WiFi] Reconfiguration cancelled, rebooting");
    RingLogger::save();
    delay(300);
    ESP.restart();
}

// ===================== WATCHDOG =====================

void watchdogInit() {
    esp_err_t err = esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true); // panic+reboot on timeout
    if (err == ESP_OK) {
        esp_task_wdt_add(NULL); // feed loop() task explicitly
        Serial.printf("[WDT] Task watchdog enabled (%ds)\n", WDT_TIMEOUT_SECONDS);
    } else {
        Serial.println("[WDT] Task watchdog init failed (continuing)");
    }
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

    auto modules = SensorRegistry::instance().activeModules();
    payload += "\"modules\":[";
    for (size_t i = 0; i < modules.size(); i++) {
        if (i > 0) payload += ",";
        payload += "\"" + String(modules[i]->moduleName()) + "\"";
    }
    payload += "]}";
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

    if (msg.indexOf("restart") >= 0) {
        RingLogger::save();
        ESP.restart();
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

    String clientId = String(MQTT_CLIENT_ID) + "_" + String(random(1000));
    Serial.print("[MQTT] Connecting...");

    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
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
struct RemoteSensor {
    uint8_t typeId;
    char name[32];
    uint8_t metricCount;   // metrics contributed by this sensor
    uint8_t metricOffset;  // index into module's flattened metric list
};

struct RemoteModule {
    uint8_t moduleId;
    RemoteSensor sensors[8];
    uint8_t sensorCount;
    char metricKeys[8][24];
    char metricUnits[8][8];
    uint8_t metricCount;   // total metrics across all sensors (<= 8)
    uint8_t values[8 * 4]; // last received raw float values
    uint8_t valueCount;
    bool hasData;
};

RemoteModule remoteModules[8];
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
    if (remoteModuleCount >= 8) return nullptr;

    mod = &remoteModules[remoteModuleCount++];
    memset(mod, 0, sizeof(RemoteModule));
    mod->moduleId = moduleId;
    return mod;
}

void uartProcessRegister(uint8_t moduleId, uint8_t* payload, uint8_t len) {
    RemoteModule* mod = findOrCreateRemoteModule(moduleId);
    if (mod == nullptr) {
        Serial.println("[UART] Too many modules!");
        LOG_INFO("UART", "Too many modules!");
        return;
    }

    // A register frame fully describes the module: reset any previous
    // registration so repeated (periodic) registers stay idempotent.
    memset(mod, 0, sizeof(RemoteModule));
    mod->moduleId = moduleId;

    uint16_t idx = 0;
    if (idx >= len) return;
    uint8_t sensorCount = payload[idx++];
    mod->sensorCount = sensorCount > 8 ? 8 : sensorCount;

    for (uint8_t s = 0; s < mod->sensorCount; s++) {
        RemoteSensor& sensor = mod->sensors[s];

        if (idx + 2 > len) return;
        sensor.typeId = payload[idx++];

        uint8_t nameLen = payload[idx++];
        if (idx + nameLen > len || nameLen > 31) return;
        memcpy(sensor.name, payload + idx, nameLen);
        sensor.name[nameLen] = '\0';
        idx += nameLen;

        if (idx >= len) return;
        uint8_t metricCount = payload[idx++];
        sensor.metricCount = metricCount > 8 ? 8 : metricCount;
        sensor.metricOffset = mod->metricCount;

        for (uint8_t m = 0; m < sensor.metricCount; m++) {
            uint8_t dst = mod->metricCount;
            if (dst >= 8) return;
            if (idx + 1 > len) return;
            uint8_t keyLen = payload[idx++];
            if (idx + keyLen + 1 > len || keyLen > 23) return;
            memcpy(mod->metricKeys[dst], payload + idx, keyLen);
            mod->metricKeys[dst][keyLen] = '\0';
            idx += keyLen;

            uint8_t unitLen = payload[idx++];
            if (idx + unitLen > len || unitLen > 7) return;
            memcpy(mod->metricUnits[dst], payload + idx, unitLen);
            mod->metricUnits[dst][unitLen] = '\0';
            idx += unitLen;

            mod->metricCount++;
        }
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

void uartProcessSensorData(uint8_t moduleId, uint8_t* payload, uint8_t len) {
    RemoteModule* mod = findRemoteModule(moduleId);
    if (mod == nullptr) {
        Serial.printf("[UART] Data from unknown module %d (not registered)\n", moduleId);
        return;
    }

    if (len < 4) return;
    uint16_t idx = 4; // skip timestamp

    mod->valueCount = 0;
    while (idx + 4 <= len && mod->valueCount < 8) {
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

void sensorsInit() {
    SensorRegistry& registry = SensorRegistry::instance();

    registry.registerDriver(new BME680Module());
    registry.registerDriver(new BH1750Module());

    registry.scanI2CBus(I2C_SDA, I2C_SCL);

    Serial.printf("[System] Active modules: %d\n", registry.activeCount());
    LOG_INFO("Boot", "Active modules: %d", registry.activeCount());
}

void sensorsRead() {
    SensorRegistry& registry = SensorRegistry::instance();

    struct Sample { const char* key; float value; const char* unit; };
    Sample samples[8];
    size_t sampleCount = 0;

    auto modules = registry.activeModules(); // snapshot (internally locked)

    registry.lock(); // serialize Wire access with WS scan/read handlers
    for (auto* mod : modules) {
        auto metrics = mod->read();
        for (auto& m : metrics) {
            if (sampleCount < 8) {
                samples[sampleCount++] = { m.key, m.value, m.unit };
            }
        }
    }
    registry.unlock();

    for (size_t i = 0; i < sampleCount; i++) {
        if (mqttReady()) {
            mqttPublishMetric(samples[i].key, samples[i].value, samples[i].unit);
        }
        sdSave(samples[i].key, samples[i].value, samples[i].unit);
    }
}

// ===================== SETUP / LOOP =====================

void setup() {
    Serial.begin(115200);
    delay(1000);

    RingLogger::init();   // restore persisted logs (survive reboot history)

    MqttConfig::init();   // cache NVS "mqtt_en" flag in RAM (avoids NVS per loop)

    Serial.println("=================================");
    Serial.print  ("  IoT Modular System - ");
    Serial.println(ESP.getChipModel());
    Serial.println("  Device: " + deviceId);
    Serial.println("=================================");

    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX, UART_TX);
    LOG_INFO("Boot", "Firmware %s starting (chip %d MHz, %d MB flash)",
             FIRMWARE_VERSION, ESP.getCpuFreqMHz(), ESP.getFlashChipSize() / (1024 * 1024));

    wifiConnect();
    ntpInit();

    if (MqttConfig::enabled()) {
        mqtt.setServer(MQTT_BROKER, MQTT_PORT);
        mqtt.setBufferSize(MQTT_BUFFER_SIZE);
        mqtt.setCallback(mqttCallback);
        mqttConnect();
    } else {
        Serial.println("[MQTT] Skipping MQTT setup (disabled)");
    }

    sdInit();
    sensorsInit();

    WebServer::instance().begin(HTTP_PORT, WEBSOCKET_PORT);
    signalingInit();

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
        OtaUpdater::apply();
    }

    if (millis() - lastSdCleanup >= SD_CLEANUP_INTERVAL_MS) {
        lastSdCleanup = millis();
        sdRotateCleanup();
    }

    wifiUpdate();
    mqttUpdate();
    uartUpdate();
    ntpEnsureSynced();
    serialCmdUpdate();

    WebServer::instance().update();
    SensorRegistry::instance().checkLiveness();
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

    delay(10);
}
