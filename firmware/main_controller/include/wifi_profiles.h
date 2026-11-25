#ifndef WIFI_PROFILES_H
#define WIFI_PROFILES_H

#include <Arduino.h>
#include <vector>

// A saved Wi-Fi network. Passwords live only in NVS and are never exposed by
// the HTTP/WebSocket/serial status payloads.
struct WifiProfile {
    uint8_t id = 0;
    String ssid;
    String password;
    uint8_t priority = 1;
    bool enabled = true;
    String bssid;
    uint8_t channel = 0;
};

namespace WifiProfiles {

constexpr size_t kMaxProfiles = 8;

void init();

size_t count();
std::vector<WifiProfile> list();
bool get(uint8_t id, WifiProfile& out);

// Adds a network. If the SSID already exists the stored password/priority is
// updated instead of creating a duplicate. Returns false and fills `error`
// ("profiles_full", "missing_ssid", "nvs_write_failed").
bool add(const String& ssid, const String& password, int priority,
         uint8_t* outId, String* error);

bool update(uint8_t id, const String& password, int priority, int enabled);

// Replaces only the SSID, keeping the stored password. Used to repair profiles
// that were saved before Wi-Fi names with leading/trailing spaces were kept
// byte-for-byte.
bool updateSsid(uint8_t id, const String& ssid);
bool remove(uint8_t id);
bool reorder(const std::vector<uint8_t>& ids);

uint8_t manualId();
void setManual(uint8_t id);

uint8_t lastOkId();
void markOk(uint8_t id, const String& bssid, uint8_t channel);

void clearAll();

}  // namespace WifiProfiles

#endif
