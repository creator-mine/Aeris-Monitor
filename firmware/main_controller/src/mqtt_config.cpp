#include "mqtt_config.h"
#include <Preferences.h>
#include "config.h"

namespace MqttConfig {

static bool g_cached   = false;
static bool g_enabled  = true;

// Reads NVS once and caches the result in RAM. Called from setup() so the
// hot loop()/mqttReady() paths never touch NVS.
void init() {
    Preferences prefs;
    if (!prefs.begin("cfg", true)) {
        g_enabled = MQTT_ENABLED_DEFAULT == 1;
    } else {
        g_enabled = prefs.getBool("mqtt_en", MQTT_ENABLED_DEFAULT == 1);
        prefs.end();
    }
    g_cached = true;
}

bool enabled() {
    if (!g_cached) init();
    return g_enabled;
}

bool setEnabled(bool on) {
    Preferences prefs;
    if (!prefs.begin("cfg", false)) return false;
    bool ok = prefs.putBool("mqtt_en", on);
    prefs.end();
    if (ok) g_enabled = on; // keep RAM cache in sync with persisted value
    return ok;
}

} // namespace MqttConfig