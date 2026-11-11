#include "relay_control.h"
#include "config.h"

namespace RelayControl {

namespace {

bool g_state = false;

void writePin(bool on) {
#if RELAY_PIN >= 0
    digitalWrite(RELAY_PIN, RELAY_ACTIVE_HIGH ? (on ? HIGH : LOW) : (on ? LOW : HIGH));
#else
    (void)on;
#endif
}

}  // namespace

void init() {
#if RELAY_PIN >= 0
    pinMode(RELAY_PIN, OUTPUT);
    writePin(false);  // safe default: relay off at boot
#endif
    g_state = false;
}

bool enabled() {
#if RELAY_PIN >= 0
    return true;
#else
    return false;
#endif
}

bool state() {
    return g_state;
}

void set(bool on) {
    g_state = on;
    writePin(on);
}

bool toggle() {
    set(!g_state);
    return g_state;
}

bool handleCommand(const char* command, const char* state) {
    if (!command) return false;

    // Accept "relay:on" / "relay:off" / "relay:toggle" as a single token.
    if (strncmp(command, "relay:", 6) == 0) {
        state = command + 6;
        command = "relay";
    }
    if (strcmp(command, "relay") != 0 && strcmp(command, "actuator") != 0) {
        return false;
    }

    if (!state || strlen(state) == 0) {
        toggle();
        return true;
    }
    if (strcmp(state, "on") == 0 || strcmp(state, "1") == 0 ||
        strcmp(state, "true") == 0) {
        set(true);
        return true;
    }
    if (strcmp(state, "off") == 0 || strcmp(state, "0") == 0 ||
        strcmp(state, "false") == 0) {
        set(false);
        return true;
    }
    if (strcmp(state, "toggle") == 0) {
        toggle();
        return true;
    }
    return false;
}

String toJson() {
    String s = "{\"enabled\":";
    s += enabled() ? "true" : "false";
    s += ",\"state\":";
    s += g_state ? "true" : "false";
    s += "}";
    return s;
}

}  // namespace RelayControl
