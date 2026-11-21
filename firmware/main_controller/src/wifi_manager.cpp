#include "wifi_manager.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <esp_task_wdt.h>
#include <algorithm>
#include <vector>

#include "config.h"
#include "wifi_profiles.h"

namespace {

enum State { STATE_IDLE, STATE_CONNECTING, STATE_CONNECTED, STATE_WAIT };

struct ScanEntry {
    String ssid;
    int rssi = -127;
    bool secure = false;
    int channel = 0;
    String bssid;
};

// Weak 2.4 GHz links can need ~30 s to reassociate after a forced disconnect.
constexpr uint32_t kConnectTimeoutMs = 30000;

State g_state = STATE_IDLE;
uint8_t g_activeId = 0;
uint8_t g_attemptId = 0;
uint32_t g_connectStart = 0;
uint32_t g_nextTry = 0;
uint32_t g_backoffMs = 5000;
uint32_t g_lastRssiCheck = 0;
uint32_t g_weakSince = 0;
uint32_t g_lastSwitch = 0;
uint32_t g_failUntil[256] = {0};

std::vector<ScanEntry> g_scan;
uint32_t g_scanAt = 0;
volatile bool g_scanRequested = false;
bool g_scanRunning = false;
uint32_t g_scanStarted = 0;
bool g_scanForWeak = false;
bool g_scanJustFinished = false;

String g_pendingRequest;
uint8_t g_pendingId = 0;
uint32_t g_pendingUntil = 0;
bool g_remoteCommit = false;
String g_remoteRequest;
String g_event;

// Deferred manual switch. HTTP handlers only validate + queue; loop() runs the
// radio calls. The short delay lets the HTTP/MQTT response leave the device
// before the station link drops.
bool g_connectQueued = false;
uint8_t g_queuedId = 0;
uint32_t g_connectAt = 0;
portMUX_TYPE g_connectMux = portMUX_INITIALIZER_UNLOCKED;

void startConnect(const WifiProfile& p) {
    if (g_state == STATE_CONNECTING) {
        // Abandoning an in-flight attempt: WiFi.begin() fails with
        // ESP_ERR_WIFI_STATE ("sta is connecting") unless the station is
        // stopped first. A radio restart also clears the stale channel/BSSID.
        WiFi.disconnect(true);
    }
    WiFi.mode(WIFI_STA);
    // Always let the driver pick the BSSID/channel: a cached BSSID becomes
    // stale after a router reboot, band steering or channel change and then
    // every retry fails.
    WiFi.begin(p.ssid.c_str(), p.password.c_str());
    g_attemptId = p.id;
    g_state = STATE_CONNECTING;
    g_connectStart = millis();
    Serial.printf("[WiFi] Trying %s (id=%u, pri=%u)\n", p.ssid.c_str(),
                  (unsigned)p.id, (unsigned)p.priority);
}

bool tryBlocking(const WifiProfile& p, uint32_t timeoutMs) {
    startConnect(p);
    uint32_t start = millis();
    while (millis() - start < timeoutMs) {
        if (WiFi.status() == WL_CONNECTED) {
            g_activeId = p.id;
            g_state = STATE_CONNECTED;
            WifiProfiles::markOk(p.id, WiFi.BSSIDstr(), (uint8_t)WiFi.channel());
            return true;
        }
        delay(200);
    }
    return false;
}

std::vector<WifiProfile> enabledSorted() {
    std::vector<WifiProfile> list = WifiProfiles::list();
    std::vector<WifiProfile> out;
    for (const auto& p : list) {
        if (p.enabled) out.push_back(p);
    }
    std::sort(out.begin(), out.end(), [](const WifiProfile& a, const WifiProfile& b) {
        if (a.priority != b.priority) return a.priority < b.priority;
        return a.id < b.id;
    });
    return out;
}

void startNext() {
    uint32_t now = millis();
    std::vector<WifiProfile> candidates = enabledSorted();
    if (candidates.empty()) {
        g_state = STATE_WAIT;
        g_nextTry = now + 30000;
        return;
    }

    uint8_t manual = WifiProfiles::manualId();
    std::vector<WifiProfile> ordered;
    if (manual != 0) {
        for (const auto& p : candidates) {
            if (p.id == manual) {
                ordered.push_back(p);
                break;
            }
        }
    }
    for (const auto& p : candidates) {
        if (manual != 0 && p.id == manual) continue;
        ordered.push_back(p);
    }

    for (const auto& p : ordered) {
        if (g_failUntil[p.id] > now) continue;
        startConnect(p);
        return;
    }

    // Everything failed recently: clear the short ban and retry the cycle
    // soon instead of hammering the radios or leaving a failed remote commit
    // without a result for too long.
    for (const auto& p : ordered) g_failUntil[p.id] = 0;
    g_state = STATE_WAIT;
    g_nextTry = now + 5000;
}

void evaluateWeakSignal(int currentRssi) {
    WifiProfile current;
    if (!WifiProfiles::get(g_activeId, current)) return;

    WifiProfile best;
    int bestRssi = -127;
    bool found = false;
    for (const auto& e : g_scan) {
        if (e.ssid == current.ssid) continue;
        WifiProfile p;
        bool matched = false;
        for (const auto& candidate : WifiProfiles::list()) {
            if (candidate.enabled && candidate.ssid == e.ssid &&
                g_failUntil[candidate.id] <= millis()) {
                p = candidate;
                matched = true;
                break;
            }
        }
        if (!matched) continue;
        if (!found || p.priority < best.priority ||
            (p.priority == best.priority && e.rssi > bestRssi)) {
            best = p;
            bestRssi = e.rssi;
            found = true;
        }
    }
    if (!found) return;

    bool betterPriority = best.priority < current.priority;
    bool betterSignal = best.priority == current.priority &&
                        bestRssi > currentRssi + 10;
    if (!betterPriority && !betterSignal) return;
    if (currentRssi > -70) return;

    Serial.printf("[WiFi] Switching %s -> %s (%d dBm)\n",
                  current.ssid.c_str(), best.ssid.c_str(), bestRssi);
    g_lastSwitch = millis();
    WiFi.disconnect(false, false);
    startConnect(best);
}

void failCurrent(const char* reason) {
    uint32_t now = millis();
    g_failUntil[g_attemptId] = now + 60000;
    g_state = STATE_WAIT;
    g_nextTry = now + g_backoffMs;
    g_backoffMs = std::min<uint32_t>(g_backoffMs * 2, 60000);

    if (g_remoteCommit) {
        JsonDocument doc;
        doc["request_id"] = g_remoteRequest;
        doc["status"] = "error";
        doc["error"] = reason;
        String out;
        serializeJson(doc, out);
        g_event = out;
        g_remoteCommit = false;
        WifiProfiles::setManual(0);
        g_nextTry = now + 3000;
    } else if (g_attemptId == WifiProfiles::manualId()) {
        // Manual choice is unreachable: fall back to auto instead of staying
        // offline until the user changes it.
        WifiProfiles::setManual(0);
    }
}

}  // namespace

namespace WifiManager {

bool begin() {
    WifiProfiles::init();

    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(DEVICE_ID);
    WiFi.setAutoReconnect(false);

    std::vector<WifiProfile> profiles = enabledSorted();
    if (profiles.empty()) {
        g_state = STATE_WAIT;
        g_nextTry = millis() + 5000;
        return false;
    }

    std::vector<WifiProfile> order;
    auto pushUnique = [&order](const WifiProfile& p) {
        for (const auto& existing : order) {
            if (existing.id == p.id) return;
        }
        order.push_back(p);
    };

    uint8_t manual = WifiProfiles::manualId();
    uint8_t last = WifiProfiles::lastOkId();
    if (manual != 0) {
        for (const auto& p : profiles) {
            if (p.id == manual) pushUnique(p);
        }
    }
    if (last != 0) {
        for (const auto& p : profiles) {
            if (p.id == last) pushUnique(p);
        }
    }
    for (const auto& p : profiles) pushUnique(p);

    size_t attempts = std::min<size_t>(order.size(), 4);
    for (size_t i = 0; i < attempts; i++) {
        if (tryBlocking(order[i], 10000)) {
            g_backoffMs = 5000;
            Serial.printf("[WiFi] Connected to %s (%s)\n", order[i].ssid.c_str(),
                          WiFi.localIP().toString().c_str());
            return true;
        }
        g_failUntil[order[i].id] = millis() + 30000;
    }

    g_state = STATE_WAIT;
    g_nextTry = millis() + 3000;
    return false;
}

void update() {
    uint32_t now = millis();

    bool runQueued = false;
    uint8_t queuedId = 0;
    portENTER_CRITICAL(&g_connectMux);
    if (g_connectQueued && (int32_t)(now - g_connectAt) >= 0) {
        queuedId = g_queuedId;
        g_queuedId = 0;
        g_connectQueued = false;
        runQueued = true;
    }
    portEXIT_CRITICAL(&g_connectMux);

    if (runQueued) {
        WifiProfile p;
        if (WifiProfiles::get(queuedId, p) && p.enabled) {
            if (connected() && queuedId == g_activeId) {
                // Already on this profile: do not tear down a working link
                // (a weak C6 link can take 20+ s to reassociate).
                WifiProfiles::setManual(queuedId);
                g_failUntil[queuedId] = 0;
                if (g_remoteCommit) {
                    JsonDocument doc;
                    doc["request_id"] = g_remoteRequest;
                    doc["status"] = "ok";
                    doc["id"] = queuedId;
                    doc["ssid"] = WiFi.SSID();
                    doc["rssi"] = WiFi.RSSI();
                    String out;
                    serializeJson(doc, out);
                    g_event = out;
                    g_remoteCommit = false;
                }
            } else {
                if (connected()) WiFi.disconnect(false, false);
                startConnect(p);
            }
        } else if (g_remoteCommit) {
            JsonDocument doc;
            doc["request_id"] = g_remoteRequest;
            doc["status"] = "error";
            doc["error"] = "not_found";
            String out;
            serializeJson(doc, out);
            g_event = out;
            g_remoteCommit = false;
            WifiProfiles::setManual(0);
        }
    }
    // A queued switch just restarted the state machine with a fresh
    // g_connectStart. Do not evaluate timeouts in this same iteration: `now`
    // predates that timestamp and the unsigned subtraction would wrap.
    if (runQueued) return;

    // The WiFi API must only be used from the loop task; async HTTP handlers
    // set a flag and poll the result.
    serviceScan();
    if (g_scanJustFinished) {
        g_scanJustFinished = false;
        if (g_scanForWeak && WiFi.status() == WL_CONNECTED) {
            evaluateWeakSignal(WiFi.RSSI());
        }
        g_scanForWeak = false;
    }

    wl_status_t status = WiFi.status();

    if (status == WL_CONNECTED) {
        if (g_state != STATE_CONNECTED) {
            g_state = STATE_CONNECTED;
            // An attempt can associate after its timeout fired. Attribute the
            // link to the SSID the driver actually joined, not blindly to the
            // profile we happened to start last.
            uint8_t joinedId = g_attemptId;
            const String joinedSsid = WiFi.SSID();
            if (!joinedSsid.isEmpty()) {
                for (const auto& p : WifiProfiles::list()) {
                    if (p.ssid == joinedSsid) {
                        joinedId = p.id;
                        break;
                    }
                }
            }
            g_activeId = joinedId;
            g_backoffMs = 5000;
            for (auto& until : g_failUntil) until = 0;
            WifiProfiles::markOk(g_activeId, WiFi.BSSIDstr(), (uint8_t)WiFi.channel());
            if (g_remoteCommit) {
                JsonDocument doc;
                doc["request_id"] = g_remoteRequest;
                doc["status"] = "ok";
                doc["id"] = g_activeId;
                doc["ssid"] = WiFi.SSID();
                doc["rssi"] = WiFi.RSSI();
                String out;
                serializeJson(doc, out);
                g_event = out;
                g_remoteCommit = false;
            }
        }

        if (now - g_lastRssiCheck >= 10000) {
            g_lastRssiCheck = now;
            int rssi = WiFi.RSSI();
            if (rssi < -80) {
                if (g_weakSince == 0) g_weakSince = now;
            } else {
                g_weakSince = 0;
            }
            if (g_weakSince != 0 && now - g_weakSince > 60000 &&
                now - g_lastSwitch > 300000) {
                g_scanForWeak = true;
                requestScan();
                g_weakSince = 0;
            }
        }
        return;
    }

    if (g_state == STATE_CONNECTED) {
        g_state = STATE_WAIT;
        g_nextTry = now + 1000;
    }

    if (g_state == STATE_CONNECTING) {
        if (now - g_connectStart < kConnectTimeoutMs) return;
        Serial.printf("[WiFi] Connect timeout (id=%u)\n", (unsigned)g_attemptId);
        // Leave the driver alone: the next WiFi.begin() supersedes this
        // attempt, and an attempt that associates a moment later is still
        // credited to the right profile by the SSID match above.
        failCurrent("connect_failed");
        return;
    }

    if (g_state == STATE_WAIT && (int32_t)(now - g_nextTry) >= 0) {
        startNext();
    }
}

bool connected() {
    return WiFi.status() == WL_CONNECTED;
}

String statusJson() {
    std::vector<WifiProfile> profiles = WifiProfiles::list();
    uint8_t manual = WifiProfiles::manualId();

    JsonDocument doc;
    doc["connected"] = connected();
    doc["id"] = g_activeId;
    doc["ssid"] = WiFi.SSID();
    doc["rssi"] = connected() ? WiFi.RSSI() : 0;
    doc["ip"] = WiFi.localIP().toString();
    doc["manual"] = manual != 0;
    doc["manual_id"] = manual;
    doc["used"] = profiles.size();
    doc["max"] = WifiProfiles::kMaxProfiles;

    JsonArray arr = doc["profiles"].to<JsonArray>();
    for (const auto& p : profiles) {
        JsonObject o = arr.add<JsonObject>();
        o["id"] = p.id;
        o["ssid"] = p.ssid;
        o["priority"] = p.priority;
        o["enabled"] = p.enabled;
        o["connected"] = connected() && p.id == g_activeId;
        if (connected() && p.id == g_activeId) o["rssi"] = WiFi.RSSI();
    }

    String out;
    serializeJson(doc, out);
    return out;
}

String scanJson() {
    JsonDocument doc;
    doc["scanning"] = g_scanRequested || g_scanRunning;
    doc["age_ms"] = g_scanAt == 0 ? 0 : (millis() - g_scanAt);
    JsonArray arr = doc["networks"].to<JsonArray>();
    for (const auto& e : g_scan) {
        JsonObject o = arr.add<JsonObject>();
        o["ssid"] = e.ssid;
        o["rssi"] = e.rssi;
        o["secure"] = e.secure;
        o["channel"] = e.channel;
        o["bssid"] = e.bssid;
    }
    String out;
    serializeJson(doc, out);
    return out;
}

void serviceScan() {
    if (!g_scanRunning) {
        if (!g_scanRequested) return;
        // Non-blocking scan: WiFi.scanComplete() is polled from loop().
        WiFi.scanNetworks(true, true);
        g_scanRunning = true;
        g_scanStarted = millis();
        return;
    }

    int16_t found = WiFi.scanComplete();
    if (found == -1) {  // still running
        if (millis() - g_scanStarted > 12000) {
            WiFi.scanDelete();
            g_scanRunning = false;
            g_scanRequested = false;
            g_scanAt = millis();
        }
        return;
    }

    g_scan.clear();
    g_scanAt = millis();
    for (int i = 0; i < found && g_scan.size() < 32; i++) {
        String ssid = WiFi.SSID(i);
        if (ssid.isEmpty()) continue;
        int rssi = WiFi.RSSI(i);
        bool merged = false;
        for (auto& e : g_scan) {
            if (e.ssid == ssid) {
                if (rssi > e.rssi) {
                    e.rssi = rssi;
                    e.secure = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
                    e.channel = WiFi.channel(i);
                    e.bssid = WiFi.BSSIDstr(i);
                }
                merged = true;
                break;
            }
        }
        if (merged) continue;
        ScanEntry e;
        e.ssid = ssid;
        e.rssi = rssi;
        e.secure = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
        e.channel = WiFi.channel(i);
        e.bssid = WiFi.BSSIDstr(i);
        g_scan.push_back(e);
    }
    WiFi.scanDelete();

    std::sort(g_scan.begin(), g_scan.end(),
              [](const ScanEntry& a, const ScanEntry& b) { return a.rssi > b.rssi; });
    Serial.printf("[WiFi] Scan: %u networks\n", (unsigned)g_scan.size());

    g_scanRunning = false;
    g_scanRequested = false;
    g_scanJustFinished = true;
}
void requestScan() {
    if (!g_scanRequested) g_scanRequested = true;
}

bool scanning() {
    return g_scanRequested || g_scanRunning;
}

uint32_t scanAgeMs() {
    return g_scanAt == 0 ? 0xFFFFFFFFu : (millis() - g_scanAt);
}

bool connectTo(uint8_t id, String* error, bool remote, const String& requestId) {
    WifiProfile p;
    if (!WifiProfiles::get(id, p)) {
        if (error) *error = "not_found";
        return false;
    }
    if (!p.enabled) {
        if (error) *error = "disabled";
        return false;
    }
    if (connected() && id == g_activeId) {
        // Already on this profile: let loop() answer the remote commit without
        // tearing down a working link (a weak C6 link can take 20+ s to
        // reassociate).
        if (remote) {
            g_remoteRequest = requestId;
            g_remoteCommit = true;
            portENTER_CRITICAL(&g_connectMux);
            g_queuedId = id;
            g_connectQueued = true;
            g_connectAt = millis() + 300;
            portEXIT_CRITICAL(&g_connectMux);
            return true;
        }
        WifiProfiles::setManual(id);
        g_failUntil[id] = 0;
        return true;
    }
    WifiProfiles::setManual(id);
    g_failUntil[id] = 0;
    if (remote) {
        g_remoteRequest = requestId;
        g_remoteCommit = true;
    }
    portENTER_CRITICAL(&g_connectMux);
    g_queuedId = id;
    g_connectQueued = true;
    g_connectAt = millis() + 300;
    portEXIT_CRITICAL(&g_connectMux);
    return true;
}

void setAuto() {
    WifiProfiles::setManual(0);
}

String handleRemotePrepare(const String& json) {
    JsonDocument in;
    if (deserializeJson(in, json)) {
        return "{\"ok\":false,\"error\":\"bad_json\"}";
    }
    String requestId = String((const char*)(in["request_id"] | ""));
    uint8_t id = (uint8_t)(in["id"] | 0);
    requestId.trim();
    auto fail = [&requestId](const char* error) {
        JsonDocument out;
        out["ok"] = false;
        out["error"] = error;
        if (!requestId.isEmpty()) out["request_id"] = requestId;
        String text;
        serializeJson(out, text);
        return text;
    };
    if (requestId.isEmpty() || id == 0) {
        return fail("bad_request");
    }
    WifiProfile p;
    if (!WifiProfiles::get(id, p) || !p.enabled) {
        return fail("not_found");
    }

    g_pendingRequest = requestId;
    g_pendingId = id;
    g_pendingUntil = millis() + 120000;

    JsonDocument out;
    out["ok"] = true;
    out["status"] = "prepared";
    out["request_id"] = requestId;
    out["id"] = id;
    out["ssid"] = p.ssid;
    String text;
    serializeJson(out, text);
    return text;
}

String handleRemoteCommit(const String& json) {
    JsonDocument in;
    if (deserializeJson(in, json)) {
        return "{\"ok\":false,\"error\":\"bad_json\"}";
    }
    String requestId = String((const char*)(in["request_id"] | ""));
    requestId.trim();
    auto fail = [&requestId](const String& error) {
        JsonDocument out;
        out["ok"] = false;
        out["error"] = error;
        if (!requestId.isEmpty()) out["request_id"] = requestId;
        String text;
        serializeJson(out, text);
        return text;
    };
    if (requestId.isEmpty() || requestId != g_pendingRequest ||
        g_pendingId == 0 || (int32_t)(millis() - g_pendingUntil) > 0) {
        return fail("no_pending_request");
    }

    String error;
    if (!connectTo(g_pendingId, &error, true, requestId)) {
        return fail(error);
    }
    g_pendingRequest = "";
    g_pendingId = 0;

    JsonDocument out;
    out["ok"] = true;
    out["status"] = "committing";
    out["request_id"] = requestId;
    String text;
    serializeJson(out, text);
    return text;
}

String takeEvent() {
    String out = g_event;
    g_event = "";
    return out;
}

}  // namespace WifiManager

