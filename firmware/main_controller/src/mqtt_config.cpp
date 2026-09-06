#include "mqtt_config.h"
#include <Preferences.h>
#include "config.h"

namespace MqttConfig {

bool enabled() {
    Preferences prefs;
    if (!prefs.begin("cfg", true)) {
        return MQTT_ENABLED_DEFAULT == 1;
    }
    bool value = prefs.getBool("mqtt_en", MQTT_ENABLED_DEFAULT == 1);
    prefs.end();
    return value;
}

bool setEnabled(bool on) {
    Preferences prefs;
    if (!prefs.begin("cfg", false)) return false;
    bool ok = prefs.putBool("mqtt_en", on);
    prefs.end();
    return ok;
}

} // namespace MqttConfig