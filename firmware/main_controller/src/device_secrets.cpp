#include "device_secrets.h"
#include "config.h"
#include <Preferences.h>

namespace DeviceSecrets {

namespace {

constexpr const char* NS = "secrets";

String g_user;
String g_pass;
String g_token;
bool g_loaded = false;

void loadFromNvs() {
    Preferences prefs;
    if (!prefs.begin(NS, true)) return;
    g_user = prefs.getString("mqtt_user", "");
    g_pass = prefs.getString("mqtt_pass", "");
    g_token = prefs.getString("sig_token", "");
    prefs.end();
}

void persist(const String& user, const String& pass, const String& token) {
    Preferences prefs;
    if (!prefs.begin(NS, false)) return;
    if (!user.isEmpty()) prefs.putString("mqtt_user", user);
    if (!pass.isEmpty()) prefs.putString("mqtt_pass", pass);
    if (!token.isEmpty()) prefs.putString("sig_token", token);
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
    if (g_token.isEmpty() && strlen(SIGNALING_TOKEN) > 0) {
        g_token = SIGNALING_TOKEN;
        migrated = true;
    }
    if (migrated) persist(g_user, g_pass, g_token);

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

String signalingToken() {
    init();
    return g_token;
}

bool save(const String& user, const String& password, const String& token) {
    if (user.isEmpty() && password.isEmpty() && token.isEmpty()) return false;

    Preferences prefs;
    if (!prefs.begin(NS, false)) return false;

    bool ok = true;
    if (!user.isEmpty()) ok = prefs.putString("mqtt_user", user) > 0 && ok;
    if (!password.isEmpty()) ok = prefs.putString("mqtt_pass", password) > 0 && ok;
    if (!token.isEmpty()) ok = prefs.putString("sig_token", token) > 0 && ok;
    prefs.end();

    if (!ok) return false;

    if (!user.isEmpty()) g_user = user;
    if (!password.isEmpty()) g_pass = password;
    if (!token.isEmpty()) g_token = token;
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
    g_token = "";
    g_loaded = true;
    return true;
}

bool provisioned() {
    init();
    return !g_pass.isEmpty() || !g_token.isEmpty();
}

}  // namespace DeviceSecrets
