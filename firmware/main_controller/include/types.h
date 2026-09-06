#ifndef TYPES_H
#define TYPES_H

#include <Arduino.h>

// Sensor Data Structure
struct SensorData {
    String deviceId;
    String sensorType;
    unsigned long timestamp;
    float value;
    String unit;
};

// Module Status
enum ModuleStatus {
    MODULE_OFFLINE,
    MODULE_ONLINE,
    MODULE_ERROR,
    MODULE_UPDATING
};

// Module Command
struct ModuleCommand {
    uint8_t moduleId;
    uint8_t command;
    uint8_t* payload;
    uint8_t payloadLength;
};

// Module Response
struct ModuleResponse {
    uint8_t moduleId;
    uint8_t status;
    uint8_t* data;
    uint8_t dataLength;
};

// UART Protocol
#define UART_HEADER_BYTE1 0xAA
#define UART_HEADER_BYTE2 0x55

// UART Commands
#define CMD_REGISTER      0x01
#define CMD_READ_SENSOR   0x02
#define CMD_SENSOR_DATA   0x03
#define CMD_HEARTBEAT     0x04
#define CMD_CONFIG_UPDATE 0x05
#define CMD_ACK           0x06
#define CMD_NACK          0x07

// Sensor Types
enum SensorType {
    SENSOR_UNKNOWN,
    SENSOR_BME680,
    SENSOR_BH1750,
    SENSOR_CUSTOM
};

// Device State
struct DeviceState {
    bool wifiConnected;
    bool mqttConnected;
    bool sdCardMounted;
    unsigned long lastHeartbeat;
    unsigned long lastSensorRead;
    unsigned long lastModuleCheck;
    uint32_t freeHeap;
    uint32_t uptime;
};

// Data Point for SD Card
struct DataPoint {
    unsigned long timestamp;
    String sensorType;
    float value;
    String unit;
};

#endif // TYPES_H
