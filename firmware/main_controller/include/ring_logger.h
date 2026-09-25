#ifndef RING_LOGGER_H
#define RING_LOGGER_H

#include <Arduino.h>
#include "config.h"

/**
 * Minimal in-memory ring buffer of tagged log entries.
 * Used by the web API (/api/v1/logs) and WebSocket (request_logs)
 * so the mobile app can display recent device logs.
 *
 * Each entry is ~96 bytes; 64 entries ≈ 6 KB RAM.
 */
struct LogEntry {
    uint32_t ts;          // millis() at time of logging
    char tag[12];         // short category: "WiFi", "MQTT", "Boot", …
    char msg[80];         // human-readable message
};

namespace RingLogger {

// Load ring entries persisted to NVS by a previous save() (call this once
// near the start of setup(), before any logging, to preserve the pre-boot
// history). Idempotent.
void init();

// Append a log entry.  Both `tag` and `fmt` are required; printf-style.
void log(const char* tag, const char* fmt, ...);

// Return the last `maxEntries` entries as a JSON array string.
// Caller is responsible for calling `free()` on the returned buffer
// if the string is large, or may pass a String& to avoid malloc.
String toJson(uint16_t maxEntries = 0);   // 0 = all stored

// Number of entries currently stored (up to LOG_MAX_ENTRIES).
uint16_t count();

// Clear all entries (RAM ring only).
void clear();

// Persist the current ring to NVS so it survives a reboot. Call this right
// before ESP.restart() to preserve the reboot reason in the on-boot logs.
void save();

}  // namespace RingLogger

// Convenience macros that mirror Serial.printf but also store in ring buffer.
#define LOG_INFO(tag, ...)  do { RingLogger::log(tag, __VA_ARGS__); } while (0)

#endif
