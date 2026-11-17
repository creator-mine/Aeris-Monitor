#include "device_secrets.h"
#include "config.h"
#include <Preferences.h>

namespace DeviceSecrets {

namespace {

constexpr const char* NS = "secrets";

String g_user;
String g_pass;
bool g_loaded = false;

void loadFromNvs() {
    Preferences prefs;
    if (!prefs.begin(NS, true)) return;
    g_user = prefs.getString("mqtt_user", "");
    g_pass = prefs.getString("mqtt_pass", "");
    prefs.end();
}

void persist(const String& user, const String& pass) {
    Preferences prefs;
    if (!prefs.begin(NS, false)) return;
    if (!user.isEmpty()) prefs.putString("mqtt_user", user);
    if (!pass.isEmpty()) prefs.putString("mqtt_pass", pass);
    prefs.end();
}

// Older firmware stored a separate signaling token. The API now uses the
// MQTT login (HTTP Basic), so the leftover key is removed once.
void dropLegacyToken() {
    Preferences prefs;
    if (!prefs.begin(NS, false)) return;
    if (prefs.isKey("sig_token")) prefs.remove("sig_token");
    prefs.end();
}

}  // namespace

void init() {
    if (g_loaded) return;

    loadFromNvs();

    // One-time migration: move compile-time fallbacks into NVS so a later
    // release build without secrets still has working credentials.
    bool migrated = false;
    if (g_user.isEmpty() && strlen(MQTT_USER) > 0) {
        g_user = MQTT_USER;
        migrated = true;
    }
    if (g_pass.isEmpty() && strlen(MQTT_PASSWORD) > 0) {
        g_pass = MQTT_PASSWORD;
        migrated = true;
    }
    if (migrated) persist(g_user, g_pass);

    dropLegacyToken();
    g_loaded = true;
}

String mqttUser() {
    init();
    return g_user;
}

String mqttPassword() {
    init();
    return g_pass;
}

bool save(const String& user, const String& password) {
    if (user.isEmpty() && password.isEmpty()) return false;

    Preferences prefs;
    if (!prefs.begin(NS, false)) return false;

    bool ok = true;
    if (!user.isEmpty()) ok = prefs.putString("mqtt_user", user) > 0 && ok;
    if (!password.isEmpty()) ok = prefs.putString("mqtt_pass", password) > 0 && ok;
    prefs.end();

    if (!ok) return false;

    if (!user.isEmpty()) g_user = user;
    if (!password.isEmpty()) g_pass = password;
    g_loaded = true;
    return true;
}

bool clear() {
    Preferences prefs;
    if (!prefs.begin(NS, false)) return false;
    prefs.clear();
    prefs.end();
    g_user = "";
    g_pass = "";
    g_loaded = true;
    return true;
}

bool provisioned() {
    init();
    return !g_pass.isEmpty();
}

}  // namespace DeviceSecrets
