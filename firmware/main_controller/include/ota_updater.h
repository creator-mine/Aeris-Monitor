#ifndef OTA_UPDATER_H
#define OTA_UPDATER_H

#include <Arduino.h>

/**
 * Pull-based OTA: command "ota" flags a request; the main loop then
 * downloads the published manifest (/fw/version.json) first and skips when
 * the running FIRMWARE_VERSION is already current, then downloads
 * OTA_FW_PATH over HTTPS (ISRG Root X1 pinned in root_ca.h), verifies the
 * SHA-256 (when the manifest provides one) and flashes it via the Update
 * engine. Requires OTA partition table. Pass force=true to bypass the
 * version check and re-flash even when versions match.
 */
namespace OtaUpdater {
    bool request(bool force = false); // flag one update (false if one is already pending)
    bool pending();   // a request is queued, apply() should run now
    bool apply();     // check manifest + download + flash + reboot. Blocks until done.
}

#endif