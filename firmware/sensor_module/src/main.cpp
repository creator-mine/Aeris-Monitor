#include <Arduino.h>
#include <Wire.h>
#include "config.h"
#include "uart_protocol.h"
#include "modules/sensor_registry.h"
#include "modules/bme680_module.h"
#include "modules/bh1750_module.h"

// State
unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastRegistration = 0;
const unsigned long REGISTRATION_INTERVAL_MS = 30000;

// UART Buffer
uint8_t rxBuffer[UART_BUFFER_SIZE];
uint16_t rxIndex = 0;
unsigned long rxStartTime = 0;
const unsigned long RX_TIMEOUT_MS = 500;

void sendRegister() {
    auto& modules = SensorRegistry::instance().activeModules();
    if (modules.empty()) return;

    for (auto* mod : modules) {
        uint8_t payload[256];
        uint16_t idx = 0;

        payload[idx++] = mod->typeId();

        const char* name = mod->moduleName();
        uint8_t nameLen = strlen(name);
        if (idx + 1 + nameLen > 256) continue;
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

        uartWriteFrame(Serial1, MODULE_ID, CMD_REGISTER, payload, idx);
        Serial.printf("[Module] Registered: %s (type %d, %d metrics)\n",
                      name, mod->typeId(), (int)mdefs.size());
    }
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

bool parseMessage(uint8_t* data, uint16_t length) {
    if (length < 8) return false;
    if (data[0] != UART_HDR1 || data[1] != UART_HDR2) return false;

    uint16_t payloadLength = (data[4] << 8) | data[5];
    uint16_t totalLength = 8 + payloadLength;
    if (length < totalLength) return false;

    uint16_t receivedCRC = (data[totalLength - 2] << 8) | data[totalLength - 1];
    uint16_t calculatedCRC = uartCrc16(data, totalLength - 2);
    if (receivedCRC != calculatedCRC) {
        Serial.println("[Module] CRC mismatch!");
        return false;
    }

    uint8_t moduleId = data[2];
    if (moduleId != MODULE_ID && moduleId != 0xFF) return false;

    handleCommand(data[3], data + 6, payloadLength);
    return true;
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
        uint8_t byte = Serial1.read();

        if (rxIndex == 0) rxStartTime = currentTime;

        if (rxIndex < UART_BUFFER_SIZE) {
            rxBuffer[rxIndex++] = byte;

            if (rxIndex >= 8) {
                if (parseMessage(rxBuffer, rxIndex)) {
                    rxIndex = 0;
                } else if (rxIndex >= UART_BUFFER_SIZE ||
                           currentTime - rxStartTime > RX_TIMEOUT_MS) {
                    Serial.println("[Module] RX timeout/overflow, resetting buffer");
                    rxIndex = 0;
                }
            }
        } else {
            Serial.println("[Module] RX overflow, resetting buffer");
            rxIndex = 0;
        }
    }

    static unsigned long lastBlink = 0;
    if (currentTime - lastBlink >= 1000) {
        lastBlink = currentTime;
        digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    }

    delay(10);
}
