#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include "config.h"
#include "time_util.h"
#include "web_server.h"
#include "signaling_client.h"
#include "wifi_config.h"
#include "provisioning.h"
#include "mqtt_config.h"
#include "modules/sensor_registry.h"
#include "modules/bme680_module.h"
#include "modules/bh1750_module.h"

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
    }
    Serial.println();
    Serial.print("[WiFi] IP: ");
    Serial.println(WiFi.localIP());
    return true;
}

// Try connecting: first stored NVS credentials, then the static fallback.
// Returns true on success.
bool wifiTryConnect() {
    char ssid[64] = "";
    char password[64] = "";

    if (WifiConfig::load(ssid, sizeof(ssid), password, sizeof(password))) {
        Serial.println("[WiFi] Using stored credentials");
        if (wifiConnectSta(ssid, password)) return true;
        Serial.println("[WiFi] Stored credentials failed");
        WifiConfig::clear();
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
    if (wifiTryConnect()) return;

#if PROVISION_ENABLED
    Serial.println("[WiFi] No connection, starting config mode");
    Provisioning::startAndWait();
    Serial.println("[WiFi] Provisioning session ended, rebooting");
    delay(300);
    ESP.restart();
#else
    Serial.println("[WiFi] Provisioning disabled, continuing without Wi-Fi");
#endif
}

void wifiUpdate() {
    if (WiFi.status() != WL_CONNECTED) {
        if (millis() - lastReconnect > RECONNECT_INTERVAL_MS) {
            lastReconnect = millis();
            Serial.println("[WiFi] Reconnecting...");
            wifiTryConnect();
        }
    }
}

void wifiReconfigure() {
    Serial.println("[WiFi] Reconfiguration requested, entering config mode");
    WifiConfig::clear();
    bool configured = Provisioning::startAndWait();
    Serial.println(configured ? "[WiFi] New credentials saved, rebooting"
                              : "[WiFi] Reconfiguration cancelled, rebooting");
    delay(300);
    ESP.restart();
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

    auto& modules = SensorRegistry::instance().activeModules();
    payload += "\"modules\":[";
    for (size_t i = 0; i < modules.size(); i++) {
        if (i > 0) payload += ",";
        payload += "\"" + String(modules[i]->moduleName()) + "\"";
    }
    payload += "]}";
    mqtt.publish(topic.c_str(), payload.c_str());
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
    String msg;
    for (unsigned int i = 0; i < length; i++) {
        msg += (char)payload[i];
    }
    Serial.println("[MQTT] Received: " + msg);

    if (msg.indexOf("restart") >= 0) {
        ESP.restart();
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
        String cmdTopic = mqttTopic("commands");
        mqtt.subscribe(cmdTopic.c_str());
        Serial.println("[MQTT] Subscribed: " + cmdTopic);
        mqttPublishStatus();
    } else {
        Serial.println(" FAIL rc=" + String(mqtt.state()));
    }
}

void mqttUpdate() {
    if (!MqttConfig::enabled()) {
        if (mqtt.connected()) {
            Serial.println("[MQTT] Disabled, disconnecting");
            mqtt.disconnect();
            mqtt.loop();
        }
        return;
    }
    if (!mqtt.connected()) {
        if (millis() - lastReconnect > RECONNECT_INTERVAL_MS) {
            lastReconnect = millis();
            mqttConnect();
        }
    } else {
        mqtt.loop();
    }
}

// ===================== UART BRIDGE =====================

#include "uart_protocol.h"

uint8_t uartRxBuf[UART_BUFFER_SIZE];
uint16_t uartRxIdx = 0;
unsigned long uartRxStart = 0;
const unsigned long UART_RX_TIMEOUT_MS = 500;

// Registered remote modules: moduleId -> metric keys (ordered)
struct RemoteModule {
    uint8_t moduleId;
    uint8_t typeId;
    char name[32];
    char metricKeys[8][24];
    char metricUnits[8][8];
    uint8_t metricCount;
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
        return;
    }

    uint16_t idx = 0;
    mod->typeId = payload[idx++];

    uint8_t nameLen = payload[idx++];
    if (idx + nameLen > len) return;
    memcpy(mod->name, payload + idx, nameLen);
    mod->name[nameLen] = '\0';
    idx += nameLen;

    uint8_t metricCount = payload[idx++];
    mod->metricCount = metricCount > 8 ? 8 : metricCount;

    for (uint8_t m = 0; m < mod->metricCount; m++) {
        if (idx + 1 > len) return;
        uint8_t keyLen = payload[idx++];
        if (idx + keyLen + 1 > len) return;
        memcpy(mod->metricKeys[m], payload + idx, keyLen);
        mod->metricKeys[m][keyLen] = '\0';
        idx += keyLen;

        uint8_t unitLen = payload[idx++];
        if (idx + unitLen > len) return;
        memcpy(mod->metricUnits[m], payload + idx, unitLen);
        mod->metricUnits[m][unitLen] = '\0';
        idx += unitLen;
    }

    mod->hasData = false;
    Serial.printf("[UART] Module %d registered: %s (type %d, %d metrics)\n",
                  moduleId, mod->name, mod->typeId, mod->metricCount);
    for (uint8_t m = 0; m < mod->metricCount; m++) {
        Serial.printf("  [%d] %s (%s)\n", m, mod->metricKeys[m], mod->metricUnits[m]);
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

    Serial.printf("[UART] Module %d (%s) data:\n", moduleId, mod->name);
    for (uint8_t v = 0; v < mod->valueCount && v < mod->metricCount; v++) {
        float value;
        memcpy(&value, &mod->values[v * 4], 4);
        Serial.printf("  %s = %.2f %s\n", mod->metricKeys[v], value, mod->metricUnits[v]);

        if (mqttReady()) {
            mqttPublishMetric(mod->metricKeys[v], value, mod->metricUnits[v]);
        }
    }
}

void uartProcessPacket(uint8_t moduleId, uint8_t cmd, uint8_t* payload, uint8_t len) {
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
            break;
    }
}

void uartUpdate() {
    if (uartRxIdx > 0 && millis() - uartRxStart > UART_RX_TIMEOUT_MS) {
        Serial.printf("[UART] RX timeout (%d bytes stuck), resetting\n", uartRxIdx);
        uartRxIdx = 0;
    }

    while (Serial1.available()) {
        uint8_t b = Serial1.read();
        if (uartRxIdx == 0) uartRxStart = millis();
        if (uartRxIdx < UART_BUFFER_SIZE) {
            uartRxBuf[uartRxIdx++] = b;
        } else {
            Serial.printf("[UART] RX overflow, resetting\n");
            uartRxIdx = 0;
            continue;
        }
        if (uartRxIdx >= 8) {
            if (uartRxBuf[0] == UART_HDR1 && uartRxBuf[1] == UART_HDR2) {
                uint16_t payLen = (uartRxBuf[4] << 8) | uartRxBuf[5];
                uint32_t total = 8 + (uint32_t)payLen;
                if (total > UART_BUFFER_SIZE) {
                    Serial.printf("[UART] Frame too large (%d), discarding\n", total);
                    uartRxIdx = 0;
                } else if (uartRxIdx >= total) {
                    uint16_t rxCrc = (uartRxBuf[total - 2] << 8) | uartRxBuf[total - 1];
                    uint16_t calcCrc = uartCrc16(uartRxBuf, total - 2);
                    if (rxCrc == calcCrc) {
                        uartProcessPacket(uartRxBuf[2], uartRxBuf[3], uartRxBuf + 6, payLen);
                    }
                    uartRxIdx = 0;
                }
            } else {
                uartRxIdx = 0;
            }
        }
    }
}

// ===================== SD CARD =====================

bool sdMounted = false;

bool sdInit() {
    if (!SD.begin(SD_CS)) {
        Serial.println("[SD] Mount failed");
        return false;
    }
    Serial.print("[SD] Type: ");
    Serial.print(SD.cardType() == CARD_SDHC ? "SDHC" : SD.cardType() == CARD_SD ? "SD" : "Unknown");
    Serial.print(" Size: ");
    Serial.print(SD.totalBytes() / (1024 * 1024));
    Serial.println(" MB");
    sdMounted = true;
    return true;
}

void sdSave(const char* sensorType, float value, const char* unit) {
    if (!sdMounted) return;
    String path = "/data_" + String(deviceId) + ".csv";
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
}

void sensorsRead() {
    auto& modules = SensorRegistry::instance().activeModules();

    for (auto* mod : modules) {
        auto metrics = mod->read();

        for (auto& m : metrics) {
            if (mqttReady()) {
                mqttPublishMetric(m.key, m.value, m.unit);
            }
            sdSave(m.key, m.value, m.unit);
        }
    }
}

// ===================== SETUP / LOOP =====================

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println("=================================");
    Serial.println("  IoT Modular System - ESP32-C3");
    Serial.println("  Device: " + deviceId);
    Serial.println("=================================");

    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX, UART_TX);

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

    Serial.println("=================================");
    Serial.printf("  Ready! Free heap: %d\n", ESP.getFreeHeap());
    Serial.println("=================================");
}

void loop() {
    wifiUpdate();
    mqttUpdate();
    uartUpdate();

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
