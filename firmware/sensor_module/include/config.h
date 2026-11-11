#ifndef SENSOR_MODULE_CONFIG_H
#define SENSOR_MODULE_CONFIG_H

// Module Configuration
#define MODULE_ID 1
#define MODULE_NAME "Sensor Module"
#define MODULE_TYPE "esp32c6"

// I2C Configuration
#define I2C_SDA 6
#define I2C_SCL 7
#define I2C_FREQUENCY 100000

// TCA9548A mux addresses on the bus, 0-terminated. {0x00} = no mux.
// Example for one mux with A0-A2 tied low: { 0x70, 0x00 }
#ifndef I2C_MUX_ADDRESSES
#define I2C_MUX_ADDRESSES { 0x00 }
#endif

// UART Configuration (to Main Controller)
#define UART_RX 4
#define UART_TX 5
#define UART_BAUD_RATE 115200
#define UART_BUFFER_SIZE 1024

// Sensor Configuration
#define BME680_I2C_ADDRESS 0x76
#define BH1750_I2C_ADDRESS 0x23
#define SENSOR_READ_INTERVAL_MS 5000  // 5 seconds

// Timing
#define HEARTBEAT_INTERVAL_MS 30000  // 30 seconds
#define STATUS_LED_PIN 8

// Debug
#define DEBUG_SERIAL true

#endif // SENSOR_MODULE_CONFIG_H
