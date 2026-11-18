#ifndef STATUS_LED_H
#define STATUS_LED_H

#include <Arduino.h>

// Onboard status indicator. On the ESP32-S3 N16R8 controller this is the
// WS2812 RGB LED on GPIO48. Boards without a usable LED keep STATUS_LED_PIN
// at -1 and every call becomes a no-op.
enum class StatusLedState : uint8_t {
    Off,
    Boot,
    WifiConnecting,
    Provisioning,
    MqttConnecting,
    Online,
    Error,
    Ota,
};

namespace StatusLed {

// Clear any colour left over from the previous boot and start the boot flash.
void begin();

// Switch state. Safe to call every loop iteration: only a real change resets
// the animation and forces a write.
void setState(StatusLedState state);

StatusLedState state();

// Stable identifier for diagnostics ("online", "wifi_connecting", ...).
const char* stateName();

// Non-blocking animation tick. Call from loop() and from long blocking waits
// that already pump the watchdog.
void update();

// Cycle white/red/green/blue/magenta/yellow for hardware verification.
void testPattern(uint32_t durationMs = 6000);

bool testing();

}  // namespace StatusLed

#endif
