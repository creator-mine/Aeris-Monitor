#ifndef DEVICE_SECRETS_H
#define DEVICE_SECRETS_H

#include <Arduino.h>

/**
 * Runtime credentials stored in NVS (namespace "secrets").
 *
 * Priority:
 *   1. NVS values (set via the SoftAP provisioning page or serial/API).
 *   2. Compile-time fallbacks from config.h / secrets.h (development only).
 *
 * On the first boot of a firmware that still has compile-time values, init()
 * migrates them into NVS. A later release build without compiled secrets
 * (`-DAERIS_NO_COMPILED_SECRETS`) then keeps working after an OTA update.
 */
namespace DeviceSecrets {
    void init();
    String mqttUser();
    String mqttPassword();
    String signalingToken();
    bool save(const String& user, const String& password, const String& token);
    bool clear();
    bool provisioned();
}

#endif
