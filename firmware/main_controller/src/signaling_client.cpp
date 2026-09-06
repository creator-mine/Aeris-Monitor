#include "signaling_client.h"
#include "config.h"
#include "root_ca.h"
#include "modules/sensor_registry.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

static bool registered = false;
static unsigned long lastTry = 0;

static bool signalingPost(const char* path, const char* body) {
    if (WiFi.status() != WL_CONNECTED) return false;

    HTTPClient http;
    String url = String(SIGNALING_URL) + path;
    http.begin(url, ROOT_CA_CERT);
    http.setTimeout(5000);  // bound blocking HTTPS calls (loop task / WDT)
    http.addHeader("Content-Type", "application/json");
    http.addHeader("Authorization", String("Bearer ") + SIGNALING_TOKEN);
    int code = http.POST(body);
    bool ok = (code >= 200 && code < 300);
    if (!ok) {
        Serial.printf("[Signaling] POST %s -> HTTP %d\n", path, code);
    }
    http.end();
    return ok;
}

void signalingInit() {
    if (WiFi.status() != WL_CONNECTED) return;

    JsonDocument doc;
    doc["id"] = DEVICE_ID;
    doc["name"] = DEVICE_NAME;
    doc["type"] = DEVICE_TYPE;
    doc["ip"] = WiFi.localIP().toString();
    doc["port"] = HTTP_PORT;

    JsonArray sensors = doc.createNestedArray("sensors");
    auto& modules = SensorRegistry::instance().activeModules();
    for (auto* mod : modules) {
        for (auto& m : mod->metrics()) {
            sensors.add(m.key);
        }
    }

    char buf[1024];
    serializeJson(doc, buf);

    if (signalingPost("/api/v1/devices/register", buf)) {
        registered = true;
        Serial.println("[Signaling] Registered with server");
    } else {
        Serial.println("[Signaling] Register failed");
    }
}

void signalingUpdate() {
    if (millis() - lastTry < SIGNALING_HEARTBEAT_MS) return;
    lastTry = millis();

    if (WiFi.status() != WL_CONNECTED) {
        registered = false;
        return;
    }

    if (!registered) {
        signalingInit();
        return;
    }

    char body[64];
    snprintf(body, sizeof(body), "{\"id\":\"%s\"}", DEVICE_ID);

    if (!signalingPost("/api/v1/devices/heartbeat", body)) {
        registered = false; // re-register on next tick
    }
}