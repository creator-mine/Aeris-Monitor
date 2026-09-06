#include "ota_updater.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Update.h>
#include "config.h"
#include "root_ca.h"
#include "esp_task_wdt.h"

namespace {

volatile bool pendingRequest = false;

} // namespace

namespace OtaUpdater {

bool request() {
    if (pendingRequest) return false;
    pendingRequest = true;
    Serial.println("[OTA] Update requested");
    return true;
}

bool pending() {
    return pendingRequest;
}

bool apply() {
    pendingRequest = false;
    Serial.println("[OTA] Starting download...");

    WiFiClientSecure client;
    client.setCACert(ROOT_CA_CERT);

    Serial.printf("[OTA] Connecting %s:%d...\n", OTA_FW_HOST, OTA_FW_PORT);
    if (!client.connect(OTA_FW_HOST, OTA_FW_PORT)) {
        Serial.println("[OTA] HTTPS connect failed");
        return false;
    }

    client.print(String("GET ") + OTA_FW_PATH + " HTTP/1.1\r\n"
                 + "Host: " + OTA_FW_HOST + "\r\n"
                 + "Connection: close\r\n\r\n");

    unsigned long waitUntil = millis() + 15000;
    while (client.available() == 0 && millis() < waitUntil) {
        esp_task_wdt_reset();
        delay(50);
    }
    if (client.available() == 0) {
        Serial.println("[OTA] No HTTP response");
        client.stop();
        return false;
    }

    String statusLine = client.readStringUntil('\n');
    statusLine.trim();
    Serial.printf("[OTA] %s\n", statusLine.c_str());
    if (statusLine.indexOf(" 200 ") < 0 && !statusLine.startsWith("HTTP/1.1 200")) {
        Serial.println("[OTA] HTTP error status");
        client.stop();
        return false;
    }

    int contentLength = -1;
    String line;
    while (line != "\r" && client.available()) {
        line = client.readStringUntil('\n');
        line.trim();
        if (line.startsWith("Content-Length:")) {
            String cl = line.substring(15);
            cl.trim();
            contentLength = cl.toInt();
        }
    }

    if (contentLength <= 0) {
        Serial.printf("[OTA] Bad content length (%d)\n", contentLength);
        client.stop();
        return false;
    }

    if (!Update.begin(contentLength)) {
        Serial.printf("[OTA] Update.begin failed: %s\n", Update.errorString());
        client.stop();
        return false;
    }

    Serial.printf("[OTA] Downloading %d bytes...\n", contentLength);
    size_t written = 0;
    uint8_t buf[1024];
    while (written < (size_t)contentLength && client.connected()) {
        size_t n = client.available();
        if (n > 0) {
            if (n > sizeof(buf)) n = sizeof(buf);
            int r = client.readBytes(buf, n);
            if (r <= 0) break;
            written += Update.write(buf, (size_t)r);
        } else {
            delay(20);
        }
        esp_task_wdt_reset();
    }
    client.stop();

    if (written != (size_t)contentLength) {
        Serial.printf("[OTA] Short download: %u/%d\n", (unsigned int)written, contentLength);
        Update.abort();
        return false;
    }

    if (!Update.end()) {
        Serial.printf("[OTA] Update.end failed: %s\n", Update.errorString());
        return false;
    }

    Serial.println("[OTA] Success! Rebooting...");
    delay(500);
    ESP.restart();
    return true;
}

} // namespace OtaUpdater