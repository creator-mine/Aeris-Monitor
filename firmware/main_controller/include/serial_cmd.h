#ifndef SERIAL_CMD_H
#define SERIAL_CMD_H

#include <Arduino.h>

/**
 * Lightweight text command protocol over USB Serial.
 *
 * PC → ESP32:  CMD:command_name[:arg1[:arg2...]]\n
 * ESP32 → PC:  >>{json}\n
 *
 * The >> prefix lets the Flutter app distinguish responses from the
 * normal debug output the firmware already prints to Serial.
 */
void serialCmdInit();
void serialCmdUpdate();

#endif
