#ifndef RELAY_CONTROL_H
#define RELAY_CONTROL_H

#include <Arduino.h>

/**
 * Single relay/actuator output.
 *
 * Configure RELAY_PIN in config.h (or via -DRELAY_PIN=<gpio>) and
 * RELAY_ACTIVE_HIGH for the module polarity. With the default -1 the code
 * compiles but the output stays disabled, so a board without a relay is safe.
 *
 * Commands:
 *   {"command":"relay","state":"on"|"off"|"toggle"}
 *   {"relay":true|false}
 *   relay:on / relay:off / relay:toggle
 */
namespace RelayControl {
    void init();
    bool enabled();
    bool state();
    void set(bool on);
    bool toggle();
    bool handleCommand(const char* command, const char* state);
    String toJson();
}

#endif
