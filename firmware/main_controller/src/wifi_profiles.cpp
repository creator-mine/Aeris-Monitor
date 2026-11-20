#include "wifi_profiles.h"

#include <ArduinoJson.h>
#include <Preferences.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

namespace {

const char* kNamespace = "iotcfg";
const char* kProfilesKey = "wifi_profiles";
const char* kLegacySsid = "ssid";
const char* kLegacyPassword = "password";

SemaphoreHandle_t g_lock = nullptr;
std::vector<WifiProfile> g_profiles;
uint8_t g_nextId = 1;
uint8_t g_manual = 0;
uint8_t g_lastOk = 0;

void lock() {
    if (g_lock == nullptr) g_lock = xSemaphoreCreateMutex();
    if (g_lock != nullptr) xSemaphoreTake(g_lock, portMAX_DELAY);
}

void unlock() {
    if (g_lock != nullptr) xSemaphoreGive(g_lock);
}

uint8_t allocateIdLocked() {
    for (uint16_t attempt = 0; attempt < 255; attempt++) {
        uint8_t candidate = g_nextId;
        g_nextId = (g_nextId >= 255) ? 1 : (uint8_t)(g_nextId + 1);
        if (candidate == 0) continue;
        bool used = false;
        for (const auto& p : g_profiles) {
            if (p.id == candidate) {
                used = true;
                break;
            }
        }
        if (!used) return candidate;
    }
    return 0;
}

void saveLocked() {
    JsonDocument doc;
    doc["v"] = 1;
    doc["next"] = g_nextId;
    doc["manual"] = g_manual;
    doc["last"] = g_lastOk;

    JsonArray arr = doc["profiles"].to<JsonArray>();
    for (const auto& p : g_profiles) {
        JsonObject o = arr.add<JsonObject>();
        o["id"] = p.id;
        o["ssid"] = p.ssid;
        o["pass"] = p.password;
        o["pri"] = p.priority;
        o["en"] = p.enabled;
        if (!p.bssid.isEmpty()) o["bssid"] = p.bssid;
        if (p.channel != 0) o["ch"] = p.channel;
    }

    String out;
    serializeJson(doc, out);

    Preferences prefs;
    if (!prefs.begin(kNamespace, false)) return;
    prefs.putString(kProfilesKey, out);
    prefs.end();
}

void loadLocked() {
    g_profiles.clear();
    g_nextId = 1;
    g_manual = 0;
    g_lastOk = 0;

    Preferences prefs;
    if (!prefs.begin(kNamespace, false)) return;

    String raw = prefs.getString(kProfilesKey, "");
    if (!raw.isEmpty()) {
        JsonDocument doc;
        if (!deserializeJson(doc, raw)) {
            g_nextId = doc["next"] | 1;
            if (g_nextId == 0) g_nextId = 1;
            g_manual = doc["manual"] | 0;
            g_lastOk = doc["last"] | 0;
            JsonArray arr = doc["profiles"].as<JsonArray>();
            for (JsonObject o : arr) {
                if (g_profiles.size() >= WifiProfiles::kMaxProfiles) break;
                WifiProfile p;
                p.id = o["id"] | 0;
                p.ssid = String((const char*)(o["ssid"] | ""));
                p.password = String((const char*)(o["pass"] | ""));
                p.priority = (uint8_t)(o["pri"] | 1);
                p.enabled = o["en"] | true;
                p.bssid = String((const char*)(o["bssid"] | ""));
                p.channel = (uint8_t)(o["ch"] | 0);
                if (p.id != 0 && !p.ssid.isEmpty()) g_profiles.push_back(p);
            }
        }
    }

    // Migrate the single-network layout used before 1.3.7.
    if (g_profiles.empty()) {
        String ssid = prefs.getString(kLegacySsid, "");
        String pass = prefs.getString(kLegacyPassword, "");
        if (!ssid.isEmpty()) {
            WifiProfile p;
            p.id = 1;
            p.ssid = ssid;
            p.password = pass;
            p.priority = 1;
            p.enabled = true;
            g_profiles.push_back(p);
            g_nextId = 2;
            g_lastOk = 1;
        }
    }
    prefs.end();

    if (!g_profiles.empty() && raw.isEmpty()) {
        saveLocked();
        Preferences cleanup;
        if (cleanup.begin(kNamespace, false)) {
            cleanup.remove(kLegacySsid);
            cleanup.remove(kLegacyPassword);
            cleanup.end();
        }
    }
}

bool validSsid(const String& ssid) {
    return !ssid.isEmpty() && ssid.length() <= 32;
}

bool validPassword(const String& pass) {
    return pass.length() <= 64;
}

}  // namespace

namespace WifiProfiles {

void init() {
    lock();
    loadLocked();
    unlock();
}

size_t count() {
    lock();
    size_t n = g_profiles.size();
    unlock();
    return n;
}

std::vector<WifiProfile> list() {
    lock();
    std::vector<WifiProfile> copy = g_profiles;
    unlock();
    return copy;
}

bool get(uint8_t id, WifiProfile& out) {
    lock();
    bool found = false;
    for (const auto& p : g_profiles) {
        if (p.id == id) {
            out = p;
            found = true;
            break;
        }
    }
    unlock();
    return found;
}

bool add(const String& ssid, const String& password, int priority,
         uint8_t* outId, String* error) {
    if (outId) *outId = 0;
    if (!validSsid(ssid)) {
        if (error) *error = "missing_ssid";
        return false;
    }
    if (!validPassword(password)) {
        if (error) *error = "password_too_long";
        return false;
    }

    lock();

    for (auto& p : g_profiles) {
        if (p.ssid == ssid) {
            if (!password.isEmpty()) p.password = password;
            if (priority >= 1 && priority <= (int)kMaxProfiles) {
                p.priority = (uint8_t)priority;
            }
            p.enabled = true;
            saveLocked();
            if (outId) *outId = p.id;
            unlock();
            return true;
        }
    }

    if (g_profiles.size() >= kMaxProfiles) {
        if (error) *error = "profiles_full";
        unlock();
        return false;
    }

    uint8_t maxPriority = 0;
    for (const auto& p : g_profiles) {
        if (p.priority > maxPriority) maxPriority = p.priority;
    }
    uint8_t usePriority = (priority >= 1 && priority <= (int)kMaxProfiles)
                              ? (uint8_t)priority
                              : (uint8_t)(maxPriority + 1);
    if (usePriority > kMaxProfiles) usePriority = (uint8_t)kMaxProfiles;

    WifiProfile p;
    p.id = allocateIdLocked();
    if (p.id == 0) {
        if (error) *error = "id_exhausted";
        unlock();
        return false;
    }
    p.ssid = ssid;
    p.password = password;
    p.priority = usePriority;
    p.enabled = true;
    g_profiles.push_back(p);
    saveLocked();
    if (outId) *outId = p.id;
    unlock();
    return true;
}

bool update(uint8_t id, const String& password, int priority, int enabled) {
    lock();
    bool found = false;
    for (auto& p : g_profiles) {
        if (p.id != id) continue;
        if (!password.isEmpty() && validPassword(password)) p.password = password;
        if (priority >= 1 && priority <= (int)kMaxProfiles) {
            p.priority = (uint8_t)priority;
        }
        if (enabled >= 0) p.enabled = enabled != 0;
        found = true;
        break;
    }
    if (found) saveLocked();
    unlock();
    return found;
}

bool remove(uint8_t id) {
    lock();
    bool removed = false;
    for (auto it = g_profiles.begin(); it != g_profiles.end(); ++it) {
        if (it->id == id) {
            g_profiles.erase(it);
            removed = true;
            break;
        }
    }
    if (removed) {
        if (g_manual == id) g_manual = 0;
        if (g_lastOk == id) g_lastOk = 0;
        saveLocked();
    }
    unlock();
    return removed;
}

bool reorder(const std::vector<uint8_t>& ids) {
    lock();
    uint8_t nextPriority = 1;
    for (uint8_t id : ids) {
        if (nextPriority > kMaxProfiles) break;
        for (auto& p : g_profiles) {
            if (p.id == id) {
                p.priority = nextPriority++;
                break;
            }
        }
    }
    for (auto& p : g_profiles) {
        bool listed = false;
        for (uint8_t id : ids) {
            if (p.id == id) {
                listed = true;
                break;
            }
        }
        if (!listed && nextPriority <= kMaxProfiles) p.priority = nextPriority++;
    }
    saveLocked();
    unlock();
    return true;
}

uint8_t manualId() {
    lock();
    uint8_t id = g_manual;
    unlock();
    return id;
}

void setManual(uint8_t id) {
    lock();
    g_manual = id;
    saveLocked();
    unlock();
}

uint8_t lastOkId() {
    lock();
    uint8_t id = g_lastOk;
    unlock();
    return id;
}

void markOk(uint8_t id, const String& bssid, uint8_t channel) {
    lock();
    g_lastOk = id;
    for (auto& p : g_profiles) {
        if (p.id == id) {
            p.bssid = bssid;
            p.channel = channel;
            break;
        }
    }
    saveLocked();
    unlock();
}

void clearAll() {
    lock();
    g_profiles.clear();
    g_nextId = 1;
    g_manual = 0;
    g_lastOk = 0;
    Preferences prefs;
    if (prefs.begin(kNamespace, false)) {
        prefs.remove(kProfilesKey);
        prefs.remove(kLegacySsid);
        prefs.remove(kLegacyPassword);
        prefs.end();
    }
    unlock();
}

}  // namespace WifiProfiles
