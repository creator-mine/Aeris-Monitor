#include "time_util.h"
#include <WiFi.h>
#include "config.h"

static bool synced = false;

void ntpInit() {
    if (WiFi.status() != WL_CONNECTED) return;

    configTime(NTP_OFFSET_SEC, 0, NTP_SERVER);

    // Wait up to 5s for time sync
    unsigned long start = millis();
    while (time(nullptr) < 100000 && millis() - start < 5000) {
        delay(100);
    }

    time_t now = time(nullptr);
    if (now > 100000) {
        synced = true;
        Serial.printf("[NTP] Time synced: %s", ctime(&now));
    } else {
        Serial.println("[NTP] Sync failed (will retry)");
    }
}

uint64_t epochMillis() {
    time_t now = time(nullptr);
    if (now > 100000) {
        synced = true;
        return ((uint64_t)now) * 1000ULL;
    }
    return 0;
}

// Called from loop(): retries time sync periodically until it sticks.
// Handles the case where WiFi came up after the boot-time ntpInit() (or NTP
// was unreachable at boot) — otherwise timestamps stay 0 and SD logs never
// rotate to daily files.
void ntpEnsureSynced() {
    if (synced || WiFi.status() != WL_CONNECTED) return;
    static unsigned long lastTry = 0;
    unsigned long now = millis();
    if (now - lastTry < 30000) return;
    lastTry = now;
    ntpInit();
}

bool timeSynced() {
    return synced;
}
