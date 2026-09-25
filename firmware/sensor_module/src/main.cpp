#include <Arduino.h>
#include <Wire.h>
#include "config.h"
#include "uart_protocol.h"
#include <uart_frame.h>
#include "modules/sensor_registry.h"
#include <bme680_module.h>
#include <bh1750_module.h>

// State
unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastRegistration = 0;
const unsigned long REGISTRATION_INTERVAL_MS = 30000;

// UART RX: resync-aware frame parser (survives partial/corrupt frames).
UartFrameParser uartFrame;

void sendRegister() {
    auto& modules = SensorRegistry::instance().activeModules();
    if (modules.empty()) return;

    // One consolidated frame per module listing ALL its sensors, in the same
    // order sendSensorData() emits values. Payload:
    //   [sensor_count 1B]
    //   per sensor: [type_id 1B][name_len 1B][name ...][metric_count 1B]
    //       per metric: [key_len 1B][key ...][unit_len 1B][unit ...]
    uint8_t payload[256];
    uint16_t idx = 0;

    payload[idx++] = (uint8_t)modules.size();

    for (auto* mod : modules) {
        if (idx + 2 + strlen(mod->moduleName()) > 256) break;
        payload[idx++] = mod->typeId();

        const char* name = mod->moduleName();
        uint8_t nameLen = strlen(name);
        payload[idx++] = nameLen;
        memcpy(payload + idx, name, nameLen);
        idx += nameLen;

        auto mdefs = mod->metrics();
        payload[idx++] = (uint8_t)mdefs.size();
        for (auto& m : mdefs) {
            uint8_t kLen = strlen(m.key);
            uint8_t uLen = strlen(m.unit);
            if (idx + 2 + kLen + uLen > 256) break;
            payload[idx++] = kLen;
            memcpy(payload + idx, m.key, kLen);
            idx += kLen;
            payload[idx++] = uLen;
            memcpy(payload + idx, m.unit, uLen);
            idx += uLen;
        }
    }

    uartWriteFrame(Serial1, MODULE_ID, CMD_REGISTER, payload, idx);
    Serial.printf("[Module] Registered: %d sensor(s)\n", (int)modules.size());
}

void sendSensorData() {
    auto& modules = SensorRegistry::instance().activeModules();
    if (modules.empty()) return;

    uint8_t payload[4 + 32 * 4];
    uint16_t idx = 0;

    uint32_t ts = millis();
    memcpy(payload + idx, &ts, 4);
    idx += 4;

    uint32_t count = 0;
    for (auto* mod : modules) {
        auto metrics = mod->read();
        for (auto& m : metrics) {
            if (idx + 4 >= sizeof(payload)) break;
            memcpy(payload + idx, &m.value, 4);
            idx += 4;
            count++;
        }
    }

    uartWriteFrame(Serial1, MODULE_ID, CMD_SENSOR_DATA, payload, idx);
    Serial.printf("[Module] Data sent (%d metrics)\n", count);
}

void sendHeartbeat() {
    uartWriteFrame(Serial1, MODULE_ID, CMD_HEARTBEAT, nullptr, 0);
    Serial.println("[Module] Heartbeat sent");
}

void handleCommand(uint8_t cmd, uint8_t* payload, uint8_t len) {
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
    Serial.println("IoT Modular System - Sensor Module");
    Serial.println("Module ID: " + String(MODULE_ID));
    Serial.println("=================================");

    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX, UART_TX);

    pinMode(STATUS_LED_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, LOW);

    auto& registry = SensorRegistry::instance();
    registry.registerDriver(new BME680Module());
    registry.registerDriver(new BH1750Module());
    registry.scanI2CBus(I2C_SDA, I2C_SCL);

    delay(500);
    sendRegister();
    sendSensorData();

    Serial.println("=================================");
    Serial.println("Initialization complete!");
    Serial.println("=================================");
}

void loop() {
    unsigned long currentTime = millis();

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

    while (Serial1.available()) {
        uartFrame.feed(Serial1.read(), onUartFrame, nullptr);
    }

    static unsigned long lastBlink = 0;
    if (currentTime - lastBlink >= 1000) {
        lastBlink = currentTime;
        digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    }

    delay(10);
}
