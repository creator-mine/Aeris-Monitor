#include "status_led.h"
#include "config.h"

#if STATUS_LED_ENABLED && STATUS_LED_PIN >= 0
#include <esp32-hal-rgb-led.h>
#endif

namespace {

StatusLedState currentState = StatusLedState::Off;
unsigned long stateSince = 0;
unsigned long lastTick = 0;
unsigned long testUntil = 0;
bool forceWrite = true;
bool haveWritten = false;
uint8_t lastR = 0;
uint8_t lastG = 0;
uint8_t lastB = 0;

// STATUS_LED_BRIGHTNESS caps every colour so a WS2812 is readable at night
// instead of blinding white.
uint8_t scaleChannel(uint8_t value) {
    return (uint8_t)((uint16_t)value * (STATUS_LED_BRIGHTNESS & 0xFF) / 255);
}

void writeRgb(uint8_t r, uint8_t g, uint8_t b) {
#if STATUS_LED_ENABLED && STATUS_LED_PIN >= 0
    r = scaleChannel(r);
    g = scaleChannel(g);
    b = scaleChannel(b);
    if (haveWritten && r == lastR && g == lastG && b == lastB) return;
    rgbLedWrite(STATUS_LED_PIN, r, g, b);
    lastR = r;
    lastG = g;
    lastB = b;
    haveWritten = true;
#else
    (void)r;
    (void)g;
    (void)b;
#endif
}

// Smooth 0..255 triangle over `periodMs` for the provisioning "breathing".
uint8_t breathe(unsigned long elapsed, unsigned long periodMs) {
    unsigned long phase = elapsed % periodMs;
    unsigned long half = periodMs / 2;
    unsigned long level = phase < half ? phase * 255 / half
                                       : (periodMs - phase) * 255 / half;
    // Keep a faint base so the LED never fully disappears.
    return (uint8_t)(24 + level * 231 / 255);
}

}  // namespace

namespace StatusLed {

void begin() {
    stateSince = millis();
    currentState = StatusLedState::Boot;
    forceWrite = true;
    haveWritten = false;
    testUntil = 0;
    update();
}

void setState(StatusLedState next) {
    if (next == currentState) return;
    currentState = next;
    stateSince = millis();
    forceWrite = true;
}

StatusLedState state() {
    return currentState;
}

const char* stateName() {
    switch (currentState) {
        case StatusLedState::Off:            return "off";
        case StatusLedState::Boot:           return "boot";
        case StatusLedState::WifiConnecting: return "wifi_connecting";
        case StatusLedState::Provisioning:   return "provisioning";
        case StatusLedState::MqttConnecting: return "mqtt_connecting";
        case StatusLedState::Online:         return "online";
        case StatusLedState::Error:          return "error";
        case StatusLedState::Ota:            return "ota";
    }
    return "unknown";
}

void update() {
    unsigned long now = millis();

    // Hardware test overrides the normal state machine for a few seconds.
    if (testUntil != 0) {
        if ((long)(now - testUntil) >= 0) {
            testUntil = 0;
            forceWrite = true;
        } else {
            static const uint8_t colors[][3] = {
                {255, 255, 255},  // white
                {255, 0, 0},      // red
                {0, 255, 0},      // green
                {0, 0, 255},      // blue
                {255, 0, 255},    // magenta
                {255, 180, 0},    // amber
            };
            size_t index = (now / 700) % (sizeof(colors) / sizeof(colors[0]));
            writeRgb(colors[index][0], colors[index][1], colors[index][2]);
            return;
        }
    }

    // Animations tick at ~25 Hz; solid colours write once and then stay put.
    if (!forceWrite && now - lastTick < 40) return;
    lastTick = now;
    forceWrite = false;

    unsigned long elapsed = now - stateSince;

    switch (currentState) {
        case StatusLedState::Boot:
            // One short white flash, then dark until Wi-Fi init takes over.
            if (elapsed < 350) {
                writeRgb(180, 180, 180);
            } else {
                writeRgb(0, 0, 0);
            }
            break;

        case StatusLedState::WifiConnecting: {
            bool on = (elapsed / 500) % 2 == 0;
            writeRgb(0, 0, on ? 255 : 0);
            break;
        }

        case StatusLedState::Provisioning: {
            uint8_t level = breathe(elapsed, 2000);
            writeRgb(0, 0, level);
            break;
        }

        case StatusLedState::MqttConnecting:
            writeRgb(220, 150, 0);
            break;

        case StatusLedState::Online: {
            // Green heartbeat: mostly dim, short bright pulse every 3 s.
            unsigned long phase = elapsed % 3000;
            if (phase < 120) {
                writeRgb(0, 255, 0);
            } else {
                writeRgb(0, 48, 0);
            }
            break;
        }

        case StatusLedState::Error: {
            unsigned long phase = elapsed % 1000;
            writeRgb(phase < 200 ? 255 : 0, 0, 0);
            break;
        }

        case StatusLedState::Ota: {
            unsigned long phase = elapsed % 300;
            bool on = phase < 150;
            writeRgb(on ? 200 : 0, 0, on ? 200 : 0);
            break;
        }

        case StatusLedState::Off:
        default:
            writeRgb(0, 0, 0);
            break;
    }
}

void testPattern(uint32_t durationMs) {
    testUntil = millis() + durationMs;
    forceWrite = true;
}

bool testing() {
    return testUntil != 0;
}

}  // namespace StatusLed
