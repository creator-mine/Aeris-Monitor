#ifndef PROVISIONING_H
#define PROVISIONING_H

#include <Arduino.h>

namespace Provisioning {

// Starts a SoftAP ("IoT-Setup-<last4mac>") holding a configuration web page
// at http://192.168.4.1 where the user can enter the router SSID/password.
// Runs a blocking loop until credentials are submitted and saved (or the
// provisioning timeout elapses). Returns true if credentials were configured.
bool startAndWait();

}  // namespace Provisioning

#endif