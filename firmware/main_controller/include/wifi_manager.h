#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>

namespace WifiManager {

// Boot path: tries the manual/last/priority profiles. Returns true when a
// station connection was established.
bool begin();

// Initialises profiles and station mode without attempting a connection.
// Used when Ethernet already provides the uplink; update() can start Wi-Fi
// later if the cable disappears.
void prepare();

// Runtime state machine; call from loop(). When allowConnect is false (for
// example while Ethernet is the active uplink) scans and explicit manual
// switches still run, but no automatic connection attempts are made.
void update(bool allowConnect = true);

bool connected();
String statusJson();
String scanJson();

// Asks loop() to run an asynchronous scan. The HTTP handler returns
// immediately; the app polls scanJson() until "scanning" becomes false.
void requestScan();
void serviceScan();
bool scanning();
uint32_t scanAgeMs();

// Manual selection. Validates the profile and queues the switch; loop() then
// performs WiFi.disconnect()/WiFi.begin(). Calling those from the
// AsyncWebServer task can panic the single-core C6, so HTTP handlers must
// never touch the radio directly. `remote` marks a two-phase commit whose
// final result is published on iot/<id>/wifi/result.
bool connectTo(uint8_t id, String* error, bool remote = false,
               const String& requestId = String());
void setAuto();

// Remote two-phase switch (MQTT). Both return a JSON response string.
String handleRemotePrepare(const String& json);
String handleRemoteCommit(const String& json);

// Pending result to publish on iot/<id>/wifi/result (empty when none).
String takeEvent();

}  // namespace WifiManager

#endif
