#include "lan_discovery.h"
#include "config.h"
#include "ring_logger.h"
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPmDNS.h>

namespace {

constexpr uint16_t DISCOVERY_PORT = 8266;
constexpr const char* DISCOVERY_MAGIC = "AERIS_DISCOVER_V1";

WiFiUDP udp;
bool started = false;
char mdnsHost[40] = {0};

void buildHostName() {
    snprintf(mdnsHost, sizeof(mdnsHost), "aeris-%s", DEVICE_ID);
    for (char* p = mdnsHost; *p; ++p) {
        if (*p == '_' || *p == ' ') *p = '-';
    }
}

void replyToDiscovery() {
    String ip = WiFi.localIP().toString();
    char reply[256];
    snprintf(reply, sizeof(reply),
             "{\"id\":\"%s\",\"name\":\"%s\",\"type\":\"%s\",\"fw\":\"%s\","
             "\"ip\":\"%s\",\"port\":%u,\"uptime\":%lu}",
             DEVICE_ID, DEVICE_NAME, DEVICE_TYPE, FIRMWARE_VERSION,
             ip.c_str(), (unsigned)HTTP_PORT, (unsigned long)(millis() / 1000));

    udp.beginPacket(udp.remoteIP(), udp.remotePort());
    udp.write((const uint8_t*)reply, strlen(reply));
    udp.endPacket();
}

}  // namespace

namespace LanDiscovery {

void begin() {
    if (started || WiFi.status() != WL_CONNECTED) return;

    buildHostName();
    if (MDNS.begin(mdnsHost)) {
        MDNS.addService("aeris", "tcp", HTTP_PORT);
        MDNS.addServiceTxt("aeris", "tcp", "id", DEVICE_ID);
        MDNS.addServiceTxt("aeris", "tcp", "type", DEVICE_TYPE);
        MDNS.addServiceTxt("aeris", "tcp", "fw", FIRMWARE_VERSION);
        MDNS.addService("http", "tcp", HTTP_PORT);
    }

    udp.begin(DISCOVERY_PORT);
    started = true;
    LOG_INFO("LAN", "Discovery on %s.local, UDP %u", mdnsHost, DISCOVERY_PORT);
    Serial.printf("[LAN] %s.local, UDP %u\n", mdnsHost, DISCOVERY_PORT);
}

void end() {
    if (!started) return;
    MDNS.end();
    udp.stop();
    started = false;
}

void update() {
    if (WiFi.status() != WL_CONNECTED) {
        if (started) end();
        return;
    }
    if (!started) {
        begin();
        return;
    }

    int size = udp.parsePacket();
    if (size <= 0) return;

    char buf[40];
    int n = udp.read(buf, sizeof(buf) - 1);
    if (n <= 0) return;
    buf[n] = '\0';

    if (strncmp(buf, DISCOVERY_MAGIC, strlen(DISCOVERY_MAGIC)) == 0) {
        replyToDiscovery();
    }
}

bool active() {
    return started;
}

}  // namespace LanDiscovery
