#ifndef MQTT_CONFIG_H
#define MQTT_CONFIG_H

#include <Arduino.h>

/**
 * Runtime MQTT switch stored in NVS (namespace "cfg", key "mqtt_en").
 * Default comes from MQTT_ENABLED_DEFAULT in config.h (1 = enabled).
 * Command "mqtt_enable" / "mqtt_disable" toggles it without reflashing.
 */
namespace MqttConfig {
    bool enabled();
    bool setEnabled(bool on);
}

#endif