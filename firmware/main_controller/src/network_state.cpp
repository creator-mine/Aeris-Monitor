#include "network_state.h"

#include "config.h"
#include "wifi_manager.h"

#include <WiFi.h>
#include <SPI.h>

#if AERIS_ETH_ENABLED
#include <ETH.h>
#endif

namespace {

#if AERIS_ETH_ENABLED
bool g_ethStarted = false;
bool g_ethWasUp = false;

constexpr uint32_t kEthLinkWaitMs = 2500;
constexpr uint32_t kEthDhcpWaitMs = 10000;

bool ethernetIpReady() {
    if (!g_ethStarted || !ETH.linkUp()) return false;
    return (uint32_t)ETH.localIP() != 0;
}
#endif
bool g_wifiPrepared = false;

void startEthernet() {
#if AERIS_ETH_ENABLED
    if (g_ethStarted) return;

#if AERIS_ETH_SHARE_SPI
    // The C6 has a single general-purpose SPI host. Initialise the shared bus
    // first; SD.begin() later reuses it instead of resetting it.
    SPI.begin();
    g_ethStarted = ETH.begin(ETH_PHY_W5500, ETH_PHY_ADDR, ETH_CS_PIN,
                             ETH_IRQ_PIN, ETH_RST_PIN, SPI, ETH_SPI_FREQ_MHZ);
#else
    g_ethStarted = ETH.begin(ETH_PHY_W5500, ETH_PHY_ADDR, ETH_CS_PIN,
                             ETH_IRQ_PIN, ETH_RST_PIN, ETH_SPI_HOST,
                             ETH_SCK_PIN, ETH_MISO_PIN, ETH_MOSI_PIN,
                             ETH_SPI_FREQ_MHZ);
#endif

    if (g_ethStarted) {
        ETH.setHostname(DEVICE_ID);
        Serial.printf("[NET] W5500 started (CS=%d IRQ=%d RST=%d)\n",
                      ETH_CS_PIN, ETH_IRQ_PIN, ETH_RST_PIN);
    } else {
        Serial.println("[NET] W5500 init failed, continuing on Wi-Fi");
    }
#endif
}

bool waitForEthernet() {
#if AERIS_ETH_ENABLED
    if (!g_ethStarted) return false;
    const uint32_t start = millis();
    while (!ETH.linkUp() && millis() - start < kEthLinkWaitMs) {
        delay(50);
    }
    if (!ETH.linkUp()) return false;
    while (!ethernetIpReady() && millis() - start < kEthDhcpWaitMs) {
        delay(50);
    }
    return ethernetIpReady();
#else
    return false;
#endif
}

}  // namespace

namespace NetworkState {

bool begin() {
    startEthernet();

    if (waitForEthernet()) {
#if AERIS_ETH_ENABLED
        ETH.setDefault();
        g_ethWasUp = true;
#endif
        // Keep the radio ready but do not burn power/airtime connecting it;
        // the Wi-Fi state machine starts only if the cable disappears.
        WifiManager::prepare();
        g_wifiPrepared = true;
        Serial.printf("[NET] Using Ethernet %s\n", localIP().c_str());
        return true;
    }

    Serial.println("[NET] Ethernet link unavailable, using Wi-Fi");
    const bool wifi = WifiManager::begin();
    g_wifiPrepared = true;
#if AERIS_ETH_ENABLED
    g_ethWasUp = ethernetUp();
#endif
    return wifi || connected();
}

void update() {
#if AERIS_ETH_ENABLED
    const bool up = ethernetUp();
    if (up != g_ethWasUp) {
        g_ethWasUp = up;
        if (up) {
            ETH.setDefault();
            Serial.printf("[NET] Ethernet link up (%u Mbps, %s)\n",
                          (unsigned)ETH.linkSpeed(), localIP().c_str());
        } else {
            // Give the route back to Wi-Fi when the cable disappears. The
            // netif may not be up yet; Wi-Fi becomes the default as soon as
            // it associates.
            esp_netif_t* wifiNetif =
                esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
            if (wifiNetif) esp_netif_set_default_netif(wifiNetif);
            Serial.println("[NET] Ethernet link down, falling back to Wi-Fi");
        }
    }
    // Ethernet priority: leave an existing Wi-Fi link alone as a warm standby,
    // but do not run automatic reconnects while the cable carries traffic.
    if (up) {
        WifiManager::update(false);
        return;
    }
#endif

    if (!g_wifiPrepared) {
        WifiManager::prepare();
        g_wifiPrepared = true;
    }
    WifiManager::update(true);
}

bool connected() {
    if (ethernetUp()) return true;
    return WifiManager::connected();
}

bool ethernetLink() {
#if AERIS_ETH_ENABLED
    return g_ethStarted && ETH.linkUp();
#else
    return false;
#endif
}

bool ethernetUp() {
#if AERIS_ETH_ENABLED
    return ethernetIpReady();
#else
    return false;
#endif
}

bool wifiUp() {
    return WifiManager::connected();
}

String type() {
    if (ethernetUp()) return "ethernet";
    if (WifiManager::connected()) return "wifi";
    return "none";
}

String localIP() {
    if (ethernetUp()) {
#if AERIS_ETH_ENABLED
        return ETH.localIP().toString();
#endif
    }
    return WiFi.localIP().toString();
}

String ethernetIp() {
#if AERIS_ETH_ENABLED
    if (g_ethStarted) return ETH.localIP().toString();
#endif
    return "";
}

uint16_t ethernetSpeed() {
#if AERIS_ETH_ENABLED
    if (g_ethStarted) return ETH.linkSpeed();
#endif
    return 0;
}

String ssid() {
    return WifiManager::connected() ? WiFi.SSID() : String("");
}

int rssi() {
    return WifiManager::connected() ? (int)WiFi.RSSI() : 0;
}

}  // namespace NetworkState
