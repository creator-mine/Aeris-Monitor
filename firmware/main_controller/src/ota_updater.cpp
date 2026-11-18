#include "ota_updater.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Update.h>
#include <esp_ota_ops.h>
#include "config.h"
#include "root_ca.h"
#include "ring_logger.h"
#include "status_led.h"
#include "esp_task_wdt.h"
#include "esp_idf_version.h"
#include "mbedtls/md.h"
#include <ArduinoJson.h>

namespace {

volatile bool pendingRequest = false;
volatile bool forceRequest = false;
portMUX_TYPE otaMux = portMUX_INITIALIZER_UNLOCKED;

// A firmware download runs on the loop task: TLS handshakes and flash writes
// are blocking, so the normal 20 s task watchdog is too tight and used to
// abort the update. Widen it for the duration of apply() and restore it after.
constexpr uint32_t OTA_WDT_TIMEOUT_MS = 180000;

void setWdtTimeout(uint32_t ms) {
#if defined(ESP_IDF_VERSION) && ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 3, 0)
    esp_task_wdt_config_t cfg = {};
    cfg.timeout_ms = ms;
    cfg.idle_core_mask = (1 << CONFIG_FREERTOS_NUMBER_OF_CORES) - 1;
    cfg.trigger_panic = true;
    if (esp_task_wdt_reconfigure(&cfg) != ESP_OK) {
        // TWDT not initialised yet: create it with the requested timeout.
        if (esp_task_wdt_init(&cfg) == ESP_OK) {
            esp_task_wdt_add(NULL);
        }
    }
#else
    (void)ms;
#endif
}

struct OtaWdtGuard {
    OtaWdtGuard() { setWdtTimeout(OTA_WDT_TIMEOUT_MS); }
    ~OtaWdtGuard() { setWdtTimeout((uint32_t)WDT_TIMEOUT_SECONDS * 1000); }
};

// Fetch a small HTTPS resource (headers stripped). Returns false on any failure.
bool httpsGet(const char* path, String& out, size_t maxBytes) {
    WiFiClientSecure client;
    client.setCACert(ROOT_CA_CERT);

    if (!client.connect(OTA_FW_HOST, OTA_FW_PORT)) {
        LOG_INFO("OTA", "HTTPS connect failed for %s", path);
        return false;
    }

    client.print(String("GET ") + path + " HTTP/1.1\r\n"
                 + "Host: " + OTA_FW_HOST + "\r\n"
                 + "Connection: close\r\n\r\n");

    unsigned long waitUntil = millis() + 15000;
    while (client.available() == 0 && millis() < waitUntil) {
        esp_task_wdt_reset();
        StatusLed::update();
        delay(50);
    }
    if (client.available() == 0) {
        LOG_INFO("OTA", "No HTTP response (timeout) for %s", path);
        client.stop();
        return false;
    }

    String statusLine = client.readStringUntil('\n');
    statusLine.trim();
    if (statusLine.indexOf(" 200 ") < 0 && !statusLine.startsWith("HTTP/1.1 200")) {
        LOG_INFO("OTA", "HTTP error for %s: %s", path, statusLine.c_str());
        client.stop();
        return false;
    }

    // Skip the remaining header lines (stop at the blank line, NOT when the
    // socket runs dry: the body may already be arriving).
    String line;
    while (true) {
        line = client.readStringUntil('\n');
        line.trim();
        if (line.isEmpty()) break;
        if (!client.available() && !client.connected()) break;
        esp_task_wdt_reset();
    }

    out = "";
    while (client.available() && out.length() < maxBytes) {
        out += (char)client.read();
    }
    client.stop();
    return !out.isEmpty();
}

// Numeric comparison of "major.minor.patch" (+ optional suffix ignored).
// Returns a-b (<0, 0, >0).
int versionCmp(const char* a, const char* b) {
    int x[3] = {0, 0, 0};
    int y[3] = {0, 0, 0};

    const char* pa = a;
    const char* pb = b;
    for (int i = 0; i < 3; i++) {
        x[i] = atoi(pa);
        y[i] = atoi(pb);
        pa = strchr(pa, '.');
        pb = strchr(pb, '.');
        if (!pa || !pb) break;
        pa++;
        pb++;
    }

    for (int i = 0; i < 3; i++) {
        if (x[i] != y[i]) return x[i] - y[i];
    }
    return 0;
}

} // namespace

namespace OtaUpdater {

bool request(bool force) {
    portENTER_CRITICAL(&otaMux);
    if (pendingRequest) {
        portEXIT_CRITICAL(&otaMux);
        return false;
    }
    pendingRequest = true;
    forceRequest = force;
    portEXIT_CRITICAL(&otaMux);
    LOG_INFO("OTA", "Update requested (%s)", force ? "force" : "auto");
    return true;
}

bool pending() {
    return pendingRequest;
}

bool apply() {
    OtaWdtGuard wdtGuard;
    StatusLed::setState(StatusLedState::Ota);
    StatusLed::update();
    portENTER_CRITICAL(&otaMux);
    bool force = forceRequest;
    pendingRequest = false;
    forceRequest = false;
    portEXIT_CRITICAL(&otaMux);
    LOG_INFO("OTA", "Starting update (%s)", force ? "force" : "auto");

    // 1) Check the published manifest to avoid re-flashing the same firmware.
    String manifest;
    bool haveManifest = httpsGet(OTA_VERSION_PATH, manifest, 1024);
    String publishedVersion;
    String expectedSha256;
    long manifestSize = 0;
    bool manifestOk = false;

    if (haveManifest) {
        JsonDocument doc;
        if (!deserializeJson(doc, manifest)) {
            manifestOk = true;
            const char* v = doc["version"];
            const char* h = doc["sha256"];
            if (v && v[0]) publishedVersion = String(v);
            if (h && h[0]) expectedSha256 = String(h);
            manifestSize = (long)(doc["size"] | 0);
        }
    }

    if (!force && manifestOk && !publishedVersion.isEmpty() &&
        versionCmp(FIRMWARE_VERSION, publishedVersion.c_str()) >= 0) {
        LOG_INFO("OTA", "Already up to date (%s == %s), skipping", FIRMWARE_VERSION, publishedVersion.c_str());
        return true;
    }

    if (manifestOk && !publishedVersion.isEmpty()) {
        LOG_INFO("OTA", "Updating %s -> %s", FIRMWARE_VERSION, publishedVersion.c_str());
    } else {
        // No manifest (old deployment) — proceed with a plain download.
        LOG_INFO("OTA", "No version manifest, downloading %s", OTA_FW_PATH);
    }

    // Start the update BEFORE opening the firmware connection: erasing the
    // OTA slot takes seconds, and doing it while the TLS socket is open makes
    // the link drop before the first body byte arrives.
    size_t beginSize = manifestSize > 0 ? (size_t)manifestSize : (size_t)UPDATE_SIZE_UNKNOWN;
    if (!Update.begin(beginSize)) {
        LOG_INFO("OTA", "Update.begin failed: %s", Update.errorString());
        return false;
    }

    WiFiClientSecure client;
    client.setCACert(ROOT_CA_CERT);

    if (!client.connect(OTA_FW_HOST, OTA_FW_PORT)) {
        LOG_INFO("OTA", "HTTPS connect failed");
        Update.abort();
        return false;
    }

    client.print(String("GET ") + OTA_FW_PATH + " HTTP/1.1\r\n"
                 + "Host: " + OTA_FW_HOST + "\r\n"
                 + "Connection: close\r\n\r\n");

    unsigned long waitUntil = millis() + 15000;
    while (client.available() == 0 && millis() < waitUntil) {
        esp_task_wdt_reset();
        StatusLed::update();
        delay(50);
    }
    if (client.available() == 0) {
        LOG_INFO("OTA", "No HTTP response (timeout)");
        client.stop();
        Update.abort();
        return false;
    }

    String statusLine = client.readStringUntil('\n');
    statusLine.trim();
    if (statusLine.indexOf(" 200 ") < 0 && !statusLine.startsWith("HTTP/1.1 200")) {
        LOG_INFO("OTA", "HTTP error: %s", statusLine.c_str());
        client.stop();
        Update.abort();
        return false;
    }

    int contentLength = -1;
    String line;
    while (true) {
        line = client.readStringUntil('\n');
        line.trim();
        if (line.isEmpty()) break;  // blank line: headers are over, body follows
        if (line.startsWith("Content-Length:")) {
            String cl = line.substring(15);
            cl.trim();
            contentLength = cl.toInt();
        }
        if (!client.available() && !client.connected()) break;
        esp_task_wdt_reset();
    }

    if (contentLength <= 0) {
        LOG_INFO("OTA", "Bad content length: %d", contentLength);
        client.stop();
        Update.abort();
        return false;
    }

    if (manifestSize > 0 && contentLength != manifestSize) {
        LOG_INFO("OTA", "Size mismatch: manifest %ld, server %d", manifestSize, contentLength);
        client.stop();
        Update.abort();
        return false;
    }

    // Compute SHA-256 of the stream as it is flashed (if SHA-256 expected).
    mbedtls_md_context_t mdCtx;
    bool hashing = false;
    unsigned char sha256Out[32];
    if (!expectedSha256.isEmpty() && expectedSha256.length() == 64) {
        mbedtls_md_init(&mdCtx);
        const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
        hashing = (mdInfo != nullptr) &&
                  (mbedtls_md_setup(&mdCtx, mdInfo, 0) == 0) &&
                  (mbedtls_md_starts(&mdCtx) == 0);
    }

    LOG_INFO("OTA", "Downloading %d bytes...", contentLength);
    size_t written = 0;
    uint8_t buf[1024];
    unsigned long lastData = millis();
    while (written < (size_t)contentLength) {
        size_t n = client.available();
        if (n > 0) {
            if (n > sizeof(buf)) n = sizeof(buf);
            int r = client.readBytes(buf, n);
            if (r <= 0) break;
            written += Update.write(buf, (size_t)r);
            if (hashing) mbedtls_md_update(&mdCtx, buf, (size_t)r);
            lastData = millis();
        } else {
            // Do not stop on client.connected(): the server may close right
            // after sending the body while bytes are still buffered.
            if (!client.connected()) break;
            if (millis() - lastData > 20000) break;
            StatusLed::update();
            delay(10);
        }
        esp_task_wdt_reset();
    }
    client.stop();
    if (hashing) {
        mbedtls_md_finish(&mdCtx, sha256Out);
        mbedtls_md_free(&mdCtx);
    }

    if (written != (size_t)contentLength) {
        LOG_INFO("OTA", "Short download: %u/%d", (unsigned int)written, contentLength);
        Update.abort();
        return false;
    }

    if (hashing) {
        char hex[65];
        for (int i = 0; i < 32; i++) snprintf(hex + 2 * i, 3, "%02x", sha256Out[i]);
        if (String(hex) != expectedSha256) {
            LOG_INFO("OTA", "SHA-256 mismatch, aborting");
            Update.abort();
            return false;
        }
    }

    if (!Update.end()) {
        LOG_INFO("OTA", "Update.end failed: %s", Update.errorString());
        return false;
    }

    LOG_INFO("OTA", "Success! Rebooting...");
    RingLogger::save();
    delay(500);
    ESP.restart();
    return true;
}

bool rollback() {
    const esp_partition_t* running = esp_ota_get_running_partition();
    if (running == nullptr) {
        LOG_INFO("OTA", "Rollback: no running partition");
        return false;
    }

    // Commit the running image if it is still pending verification, otherwise
    // the bootloader may undo the switch on the next reset.
    esp_ota_img_states_t state;
    if (esp_ota_get_state_partition(running, &state) == ESP_OK &&
        state == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_ota_mark_app_valid_cancel_rollback();
    }

    // The "next update" partition is the other OTA slot — the firmware that
    // was running before the last OTA update.
    const esp_partition_t* previous = esp_ota_get_next_update_partition(nullptr);
    if (previous == nullptr || previous->address == running->address) {
        LOG_INFO("OTA", "Rollback: no other OTA slot");
        return false;
    }

    uint8_t magic = 0;
    if (esp_partition_read(previous, 0, &magic, 1) != ESP_OK || magic != 0xE9) {
        LOG_INFO("OTA", "Rollback: previous slot has no image");
        return false;
    }

    if (esp_ota_set_boot_partition(previous) != ESP_OK) {
        LOG_INFO("OTA", "Rollback: set_boot_partition failed");
        return false;
    }

    LOG_INFO("OTA", "Rollback: booting %s", previous->label);
    RingLogger::save();
    delay(300);
    ESP.restart();
    return true;
}

} // namespace OtaUpdater