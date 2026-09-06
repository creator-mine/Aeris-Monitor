#ifndef OTA_UPDATER_H
#define OTA_UPDATER_H

#include <Arduino.h>

/**
 * Pull-based OTA: command "ota" flags a request; the main loop then
 * downloads OTA_FW_URL over HTTPS (ISRG Root X1 pinned in root_ca.h)
 * and flashes it via the Update engine. Requires OTA partition table.
 */
namespace OtaUpdater {
    bool request();   // flag one update (false if one is already pending)
    bool pending();   // a request is queued, apply() should run now
    bool apply();     // download + flash + reboot. Blocks until done.
}

#endif