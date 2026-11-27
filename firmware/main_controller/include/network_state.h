#ifndef NETWORK_STATE_H
#define NETWORK_STATE_H

#include <Arduino.h>

// Single place that answers "is the device on a network?" for the rest of the
// firmware. Ethernet (W5500) is preferred when a cable is present; Wi-Fi stays
// configured and is used as the fallback when the link goes away.
namespace NetworkState {

// Boot path. Starts Ethernet when enabled, waits briefly for link + DHCP, and
// otherwise falls back to the existing Wi-Fi profile logic. Returns true when
// at least one interface is usable.
bool begin();

// Runtime maintenance: watches the Ethernet link and runs the Wi-Fi state
// machine only while Ethernet is down. Call from loop().
void update();

bool connected();
bool ethernetLink();
bool ethernetUp();
bool wifiUp();

String type();      // "ethernet" | "wifi" | "none"
String localIP();   // IP of the active interface
String ethernetIp();
uint16_t ethernetSpeed();

String ssid();      // Wi-Fi SSID, empty on a wired-only link
int rssi();         // Wi-Fi RSSI, 0 when Wi-Fi is not connected

}  // namespace NetworkState

#endif
