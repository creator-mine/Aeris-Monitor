#ifndef LAN_DISCOVERY_H
#define LAN_DISCOVERY_H

/**
 * LAN discovery: mDNS host (`aeris-<device>.local`) plus a UDP responder so
 * the mobile/desktop app can find the device without the cloud server.
 */
namespace LanDiscovery {
    void begin();
    void end();
    void update();
    bool active();
}

#endif
