#include "wifi_config.h"

#include "wifi_profiles.h"

// Backwards-compatible single-network façade used by older callers
// (serial/HTTP/MQTT wifi_set, provisioning). New code should use
// WifiProfiles directly.

namespace WifiConfig {

bool load(char* ssid, size_t ssidSize, char* password, size_t passwordSize) {
    std::vector<WifiProfile> profiles = WifiProfiles::list();
    if (profiles.empty()) return false;

    uint8_t wanted = WifiProfiles::manualId();
    if (wanted == 0) wanted = WifiProfiles::lastOkId();

    const WifiProfile* chosen = nullptr;
    for (const auto& p : profiles) {
        if (p.id == wanted && p.enabled) {
            chosen = &p;
            break;
        }
    }
    if (chosen == nullptr) {
        uint8_t bestPriority = 255;
        for (const auto& p : profiles) {
            if (p.enabled && p.priority < bestPriority) {
                bestPriority = p.priority;
                chosen = &p;
            }
        }
    }
    if (chosen == nullptr) return false;
    if (chosen->ssid.length() >= ssidSize ||
        chosen->password.length() >= passwordSize) {
        return false;
    }
    chosen->ssid.toCharArray(ssid, ssidSize);
    chosen->password.toCharArray(password, passwordSize);
    return true;
}

bool save(const char* ssid, const char* password) {
    if (ssid == nullptr || password == nullptr || strlen(ssid) == 0) return false;
    String error;
    uint8_t id = 0;
    if (!WifiProfiles::add(String(ssid), String(password), 1, &id, &error)) {
        return false;
    }
    WifiProfiles::setManual(id);
    return true;
}

bool hasCredentials() {
    return WifiProfiles::count() > 0;
}

void clear() {
    WifiProfiles::clearAll();
}

}  // namespace WifiConfig
