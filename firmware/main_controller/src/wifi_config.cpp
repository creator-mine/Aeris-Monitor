#include "wifi_config.h"
#include "config.h"
#include <Preferences.h>

namespace {
const char* NVS_NAMESPACE = "iotcfg";

Preferences prefs;
}  // namespace

namespace WifiConfig {

bool load(char* ssid, size_t ssidSize, char* password, size_t passwordSize) {
    if (!prefs.begin(NVS_NAMESPACE, false)) return false;

    String s = prefs.getString("ssid", "");
    String p = prefs.getString("password", "");
    bool ok = !s.isEmpty() && s.length() < ssidSize;
    if (ok) {
        s.toCharArray(ssid, ssidSize);
        p.toCharArray(password, passwordSize);
    }
    prefs.end();
    return ok;
}

bool save(const char* ssid, const char* password) {
    if (ssid == nullptr || password == nullptr || strlen(ssid) == 0) return false;
    if (!prefs.begin(NVS_NAMESPACE, false)) return false;

    bool ok = prefs.putString("ssid", ssid) && prefs.putString("password", password);
    prefs.end();
    return ok;
}

bool hasCredentials() {
    if (!prefs.begin(NVS_NAMESPACE, false)) return false;
    String s = prefs.getString("ssid", "");
    bool ok = !s.isEmpty();
    prefs.end();
    return ok;
}

void clear() {
    if (prefs.begin(NVS_NAMESPACE, false)) {
        prefs.clear();
        prefs.end();
    }
}

}  // namespace WifiConfig