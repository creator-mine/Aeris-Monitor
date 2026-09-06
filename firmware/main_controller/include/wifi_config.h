#ifndef WIFI_CONFIG_H
#define WIFI_CONFIG_H

#include <Arduino.h>

namespace WifiConfig {

// Load SSID/password from NVS into the provided buffers (capped to size).
// Returns false when no valid credentials are stored.
bool load(char* ssid, size_t ssidSize, char* password, size_t passwordSize);

// Persist SSID/password to NVS. Returns false on failure.
bool save(const char* ssid, const char* password);

// Whether valid credentials are already stored.
bool hasCredentials();

// Forget stored credentials (used to force a fresh provisioning cycle).
void clear();

}  // namespace WifiConfig

#endif