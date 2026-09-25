#include "ring_logger.h"
#include <cstdarg>
#include <Preferences.h>

namespace RingLogger {

namespace {
    LogEntry entries[LOG_MAX_ENTRIES];
    uint16_t head = 0;   // next write position
    uint16_t stored = 0; // how many valid entries (0..LOG_MAX_ENTRIES)

    // Guards the ring state (head/stored/entries) shared between the Arduino
    // loopTask and the ESPAsyncWebServer async_tcp task. Short, non-blocking
    // critical sections only (no NVS/String allocation inside the lock).
    portMUX_TYPE ringMux = portMUX_INITIALIZER_UNLOCKED;

    constexpr uint16_t LOG_PERSIST_MAX = 32;  // entries kept across reboots
    const char* NVS_NAMESPACE = "iotlogs";
    const char* NVS_KEY = "ring";
}

void init() {
    Preferences prefs;
    if (!prefs.begin(NVS_NAMESPACE, true)) return;

    String data = prefs.getString(NVS_KEY, "");
    prefs.end();
    if (data.isEmpty()) return;

    // Format: group of lines "ts|tag|msg" sep by '\n'; decode oldest first,
    // most recent last, then feed into the ring to keep chronological order.
    int start = 0;
    for (;;) {
        int sep = data.indexOf('\n', start);
        String line = (sep >= 0) ? data.substring(start, sep) : data.substring(start);
        line.trim();
        if (!line.isEmpty()) {
            int c1 = line.indexOf('|');
            if (c1 > 0) {
                int c2 = line.indexOf('|', c1 + 1);
                if (c2 > c1) {
                    LogEntry e;
                    e.ts = (uint32_t)strtoul(line.substring(0, c1).c_str(), nullptr, 10);
                    String tag = line.substring(c1 + 1, c2);
                    String msg = line.substring(c2 + 1);
                    strncpy(e.tag, tag.c_str(), sizeof(e.tag) - 1);
                    e.tag[sizeof(e.tag) - 1] = '\0';
                    strncpy(e.msg, msg.c_str(), sizeof(e.msg) - 1);
                    e.msg[sizeof(e.msg) - 1] = '\0';

                    entries[head] = e;
                    head = (head + 1) % LOG_MAX_ENTRIES;
                    if (stored < LOG_MAX_ENTRIES) stored++;
                }
            }
        }
        if (sep < 0) break;
        start = sep + 1;
    }
}

void save() {
    portENTER_CRITICAL(&ringMux);

    uint16_t n = stored < LOG_PERSIST_MAX ? stored : LOG_PERSIST_MAX;
    uint16_t begin = (head + LOG_MAX_ENTRIES - n) % LOG_MAX_ENTRIES;

    String data;
    data.reserve(n * 100);
    for (uint16_t i = 0; i < n; i++) {
        if (i > 0) data += '\n';
        const LogEntry& e = entries[(begin + i) % LOG_MAX_ENTRIES];
        data += String(e.ts);
        data += '|';
        data += e.tag;
        data += '|';
        for (const char* p = e.msg; *p; p++) {
            if (*p == '\n' || *p == '\r') data += ' ';
            else data += *p;
        }
    }

    portEXIT_CRITICAL(&ringMux);

    Preferences prefs;
    if (!prefs.begin(NVS_NAMESPACE, false)) return;
    prefs.putString(NVS_KEY, data);
    prefs.end();
}

void log(const char* tag, const char* fmt, ...) {
    portENTER_CRITICAL(&ringMux);

    LogEntry& e = entries[head];
    e.ts = millis();

    // tag (safe truncate)
    strncpy(e.tag, tag, sizeof(e.tag) - 1);
    e.tag[sizeof(e.tag) - 1] = '\0';

    // message (printf-style)
    va_list args;
    va_start(args, fmt);
    vsnprintf(e.msg, sizeof(e.msg), fmt, args);
    va_end(args);

    head = (head + 1) % LOG_MAX_ENTRIES;
    if (stored < LOG_MAX_ENTRIES) stored++;

    portEXIT_CRITICAL(&ringMux);
}

String toJson(uint16_t maxEntries) {
    portENTER_CRITICAL(&ringMux);

    uint16_t n = (maxEntries == 0 || maxEntries > stored) ? stored : maxEntries;
    String json;
    json.reserve(n * 100);
    json += '[';

    for (uint16_t i = 0; i < n; i++) {
        // entries are stored oldest-first starting at (head - stored)
        uint16_t idx = (head + LOG_MAX_ENTRIES - stored + i) % LOG_MAX_ENTRIES;
        const LogEntry& e = entries[idx];
        if (i > 0) json += ',';
        json += "{\"ts\":";
        json += String(e.ts);
        json += ",\"tag\":\"";
        json += e.tag;
        json += "\",\"msg\":\"";
        for (const char* p = e.msg; *p; p++) {
            if (*p == '"' || *p == '\\') json += '\\';
            json += *p;
        }
        json += "\"}";
    }
    json += ']';

    portEXIT_CRITICAL(&ringMux);
    return json;
}

uint16_t count() {
    portENTER_CRITICAL(&ringMux);
    uint16_t n = stored;
    portEXIT_CRITICAL(&ringMux);
    return n;
}

void clear() {
    portENTER_CRITICAL(&ringMux);
    head = 0;
    stored = 0;
    portEXIT_CRITICAL(&ringMux);
}

}  // namespace RingLogger
