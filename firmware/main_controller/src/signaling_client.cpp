#include "signaling_client.h"
#include "config.h"
#include "device_secrets.h"
#include "root_ca.h"
#include "ring_logger.h"
#include "sensor_registry.h"
#include "network_state.h"
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

static bool registered = false;
static unsigned long lastTry = 0;
static String registeredIp;

static bool signalingPost(const char* path, const char* body) {
    if (!NetworkState::connected()) return false;

    HTTPClient http;
    String url = String(SIGNALING_URL) + path;
    http.begin(url, ROOT_CA_CERT);
    http.setTimeout(5000);  // bound blocking HTTPS calls (loop task / WDT)
    http.addHeader("Content-Type", "application/json");
    // The registry reuses the MQTT device login (HTTP Basic).
    String user = DeviceSecrets::mqttUser();
    String pass = DeviceSecrets::mqttPassword();
    if (!pass.isEmpty()) {
        http.setAuthorization(user.c_str(), pass.c_str());
    }
    int code = http.POST(body);
    bool ok = (code >= 200 && code < 300);
    if (!ok) {
        Serial.printf("[Signaling] POST %s -> HTTP %d\n", path, code);
        LOG_INFO("Signaling", "POST %s -> HTTP %d", path, code);
    }
    http.end();
    return ok;
}

void signalingInit() {
    if (!NetworkState::connected()) return;

    JsonDocument doc;
    doc["id"] = DEVICE_ID;
    doc["name"] = DEVICE_NAME;
    doc["type"] = DEVICE_TYPE;
    doc["ip"] = NetworkState::localIP();
    doc["network"] = NetworkState::type();
    doc["port"] = HTTP_PORT;
    doc["firmwareVersion"] = FIRMWARE_VERSION;

    JsonArray sensors = doc["sensors"].to<JsonArray>();
    auto modules = SensorRegistry::instance().activeModules();
    for (auto* mod : modules) {
        for (auto& m : mod->metrics()) {
            sensors.add(m.key);
        }
    }

    char buf[1024];
    serializeJson(doc, buf);

    if (signalingPost("/api/v1/devices/register", buf)) {
        registered = true;
        registeredIp = NetworkState::localIP();
        Serial.println("[Signaling] Registered with server");
        LOG_INFO("Signaling", "Registered with server");
    } else {
        Serial.println("[Signaling] Register failed");
        LOG_INFO("Signaling", "Register failed");
    }
}

void signalingUpdate() {
    if (millis() - lastTry < SIGNALING_HEARTBEAT_MS) return;
    lastTry = millis();

    if (!NetworkState::connected()) {
        if (registered) {
            LOG_INFO("Signaling", "Network lost, device offline");
        }
        registered = false;
        return;
    }

    if (!registered) {
        signalingInit();
        return;
    }

    // Ethernet <-> Wi-Fi failover changes the LAN address; re-register so the
    // app and server do not keep trying the old one.
    if (NetworkState::localIP() != registeredIp) {
        LOG_INFO("Signaling", "LAN address changed, re-registering");
        registered = false;
        signalingInit();
        return;
    }

    char body[80];
    snprintf(body, sizeof(body), "{\"id\":\"%s\",\"firmwareVersion\":\"%s\"}", DEVICE_ID, FIRMWARE_VERSION);

    if (!signalingPost("/api/v1/devices/heartbeat", body)) {
        LOG_INFO("Signaling", "Heartbeat failed, re-register");
        registered = false; // re-register on next tick
    }
}
