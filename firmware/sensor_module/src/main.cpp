#include <Arduino.h>
#include <Wire.h>
#include <cmath>
#include "config.h"
#include "uart_protocol.h"
#include <uart_frame.h>
#include "sensor_registry.h"

// State
unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastRegistration = 0;
unsigned long lastCompositionRevision = 0;
const unsigned long REGISTRATION_INTERVAL_MS = 30000;

// CMD_REGISTER carries every module name and metric key/unit, so it outgrows
// the original 256 bytes once a handful of drivers are present. Frames larger
// than UART_BUFFER_SIZE are rejected by the parser, so stay well below it.
#define REGISTER_PAYLOAD_MAX 512
#define DATA_PAYLOAD_MAX (4 + 64 * 4)
#define MAX_METRICS_PER_MODULE 8

// UART RX: resync-aware frame parser (survives partial/corrupt frames).
UartFrameParser uartFrame;

namespace {

struct PendingMetric {
    const char* key;
    const char* unit;
};

// Registration and data frames must describe modules and metrics in the same
// order: the controller maps incoming values onto the metric keys it learned
// in CMD_REGISTER positionally. activeRecords() is the single source of that
// order for both frames, so a module that goes offline can never shift the
// values of the modules behind it onto the wrong keys.
std::vector<ActiveModule> onlineModules() {
    return SensorRegistry::instance().activeRecords();
}

} // namespace

void sendRegister() {
    auto records = onlineModules();
    if (records.empty()) return;

    // Payload:
    //   [sensor_count 1B]
    //   per sensor: [type_id 1B][name_len 1B][name ...][metric_count 1B]
    //       per metric: [key_len 1B][key ...][unit_len 1B][unit ...]
    uint8_t payload[REGISTER_PAYLOAD_MAX];
    uint16_t idx = 0;
    uint16_t written = 0;
    bool truncated = false;

    for (auto& rec : records) {
        PendingMetric pending[MAX_METRICS_PER_MODULE];
        size_t pendingCount = 0;
        size_t needed = 2 + strlen(rec.driver->moduleName());

        auto mdefs = rec.driver->metrics();
        for (auto& m : mdefs) {
            if (pendingCount >= MAX_METRICS_PER_MODULE) break;
            pending[pendingCount++] = {m.key, m.unit};
            needed += 2 + strlen(m.key) + strlen(m.unit);
        }
        needed += 1; // metric_count byte

        if (idx + needed > REGISTER_PAYLOAD_MAX) {
            truncated = true;
            break;
        }

        payload[idx++] = rec.driver->typeId();

        const char* name = rec.driver->moduleName();
        uint8_t nameLen = strlen(name);
        payload[idx++] = nameLen;
        memcpy(payload + idx, name, nameLen);
        idx += nameLen;

        payload[idx++] = (uint8_t)pendingCount;
        for (size_t i = 0; i < pendingCount; i++) {
            uint8_t kLen = strlen(pending[i].key);
            payload[idx++] = kLen;
            memcpy(payload + idx, pending[i].key, kLen);
            idx += kLen;

            uint8_t uLen = strlen(pending[i].unit);
            payload[idx++] = uLen;
            memcpy(payload + idx, pending[i].unit, uLen);
            idx += uLen;
        }
        written++;
    }

    // The count has to describe what the frame actually contains: announcing
    // more sensors than were written makes the controller parse past the end of
    // the payload and discard the whole registration.
    payload[0] = (uint8_t)written;

    if (truncated) {
        Serial.printf("[Module] Register frame truncated at %u bytes: %u of %u sensor(s) sent\n",
                      idx, written, (unsigned)records.size());
    }

    uartWriteFrame(Serial1, MODULE_ID, CMD_REGISTER, payload, idx);
    Serial.printf("[Module] Registered: %u sensor(s), %u bytes\n", written, idx);
}

void sendSensorData() {
    auto records = onlineModules();
    if (records.empty()) return;

    // One float per metric declared in CMD_REGISTER, in the same order. The
    // registry keeps rec.cached in metrics() order with NAN for values that are
    // not available yet, so the frame layout can never drift from the
    // registration the controller learned.
    uint8_t payload[DATA_PAYLOAD_MAX];
    uint16_t idx = 0;
    uint16_t count = 0;
    uint16_t missing = 0;

    uint32_t ts = millis();
    memcpy(payload + idx, &ts, 4);
    idx += 4;

    for (auto& rec : records) {
        for (auto& m : rec.cached) {
            if (idx + 4 > DATA_PAYLOAD_MAX) {
                Serial.printf("[Module] Data frame full after %u metric(s), "
                              "increase DATA_PAYLOAD_MAX and REMOTE_MODULE_MAX_METRICS\n",
                              count);
                break;
            }
            float value = m.value;
            if (!std::isfinite(value)) {
                value = NAN; // the controller skips non-finite values
                missing++;
            }
            memcpy(payload + idx, &value, 4);
            idx += 4;
            count++;
        }
    }

    uartWriteFrame(Serial1, MODULE_ID, CMD_SENSOR_DATA, payload, idx);
    Serial.printf("[Module] Data sent (%u metric(s)%s)\n", count,
                  missing ? ", some still warming up" : "");
}

void sendHeartbeat() {
    uartWriteFrame(Serial1, MODULE_ID, CMD_HEARTBEAT, nullptr, 0);
    Serial.println("[Module] Heartbeat sent");
}

void handleCommand(uint8_t cmd, uint8_t* payload, uint16_t len) {
    switch (cmd) {
        case CMD_HEARTBEAT:
            sendHeartbeat();
            break;
        case CMD_READ_SENSOR:
            sendSensorData();
            break;
        case CMD_CONFIG_UPDATE:
            sendRegister();
            break;
        default:
            Serial.printf("[Module] Unknown command: 0x%02X\n", cmd);
            break;
    }
}

void onUartFrame(uint8_t moduleId, uint8_t cmd, uint8_t* payload,
                 uint16_t len, void* context) {
    (void)context;
    if (moduleId != MODULE_ID && moduleId != 0xFF) return;
    handleCommand(cmd, payload, len);
}

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println("=================================");
    Serial.println("Aeris Monitor - Sensor Module");
    Serial.println("Module ID: " + String(MODULE_ID));
    Serial.println("=================================");

    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX, UART_TX);

    pinMode(STATUS_LED_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, LOW);

    auto& registry = SensorRegistry::instance();

    // Drivers register themselves via REGISTER_SENSOR, so the list below is
    // not needed here and adding a sensor touches no project file.
    static const uint8_t kMuxAddresses[] = I2C_MUX_ADDRESSES;
    registry.setMuxAddresses(kMuxAddresses,
                             sizeof(kMuxAddresses) / sizeof(kMuxAddresses[0]));

    registry.scanI2CBus(I2C_SDA, I2C_SCL);
    registry.poll();

    delay(500);
    lastCompositionRevision = registry.compositionRevision();
    sendRegister();
    sendSensorData();

    Serial.println("=================================");
    Serial.println("Initialization complete!");
    Serial.println("=================================");
}

void loop() {
    unsigned long currentTime = millis();

    while (Serial1.available()) {
        uartFrame.feed(Serial1.read(), onUartFrame, nullptr);
    }

    // Honours each driver's readInterval() and caches the values, so
    // sendSensorData() and the HTTP/MQTT paths never touch the bus themselves.
    SensorRegistry::instance().poll();

    // A module appearing or disappearing changes the metric order in the data
    // frame, so the controller has to relearn the mapping.
    unsigned long revision = SensorRegistry::instance().compositionRevision();
    if (revision != lastCompositionRevision) {
        lastCompositionRevision = revision;
        lastRegistration = millis();
        sendRegister();
    }

    if (currentTime - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
        lastSensorRead = currentTime;
        sendSensorData();
    }

    if (currentTime - lastHeartbeat >= HEARTBEAT_INTERVAL_MS) {
        lastHeartbeat = currentTime;
        sendHeartbeat();
    }

    if (currentTime - lastRegistration >= REGISTRATION_INTERVAL_MS) {
        lastRegistration = currentTime;
        sendRegister();
    }

    static unsigned long lastBlink = 0;
    if (currentTime - lastBlink >= 1000) {
        lastBlink = currentTime;
        digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    }

    delay(10);
}
