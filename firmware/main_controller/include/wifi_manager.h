#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>

namespace WifiManager {

// Boot path: tries the manual/last/priority profiles. Returns true when a
// station connection was established.
bool begin();

// Runtime state machine; call from loop().
void update();

bool connected();
String statusJson();
String scanJson();
bool scanNow();

// Manual selection. On failure the manager falls back to auto.
bool connectTo(uint8_t id, String* error);
void setAuto();

// Remote two-phase switch (MQTT). Both return a JSON response string.
String handleRemotePrepare(const String& json);
String handleRemoteCommit(const String& json);

// Pending result to publish on iot/<id>/wifi/result (empty when none).
String takeEvent();

}  // namespace WifiManager

#endif
