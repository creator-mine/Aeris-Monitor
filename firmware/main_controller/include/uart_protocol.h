#ifndef UART_PROTOCOL_H
#define UART_PROTOCOL_H

#include <Arduino.h>

#define UART_HDR1 0xAA
#define UART_HDR2 0x55

// Commands
#define CMD_REGISTER      0x01  // module -> controller: type + metrics info
#define CMD_READ_SENSOR   0x02  // controller -> module: request data now
#define CMD_SENSOR_DATA   0x03  // module -> controller: metric values
#define CMD_HEARTBEAT     0x04  // both directions
#define CMD_CONFIG_UPDATE 0x05  // controller -> module: re-register / reconfigure
#define CMD_ACK           0x06
#define CMD_NACK          0x07

// Frame: [HDR1][HDR2][module_id][cmd][len_hi][len_lo][payload...][crc_hi][crc_lo]
// Header overhead = 6 bytes, CRC = 2 bytes, total = 8 + payload_len
#define UART_HEADER_SIZE 6
#define UART_CRC_SIZE 2

// CMD_REGISTER payload:
//   [type_id 1B][name_len 1B][name...][metric_count 1B]
//   per metric: [key_len 1B][key...][unit_len 1B][unit...]
//
// CMD_SENSOR_DATA payload:
//   [timestamp 4B][value1 4B float][value2 4B float]...
//   values ordered by metrics from CMD_REGISTER

static uint16_t uartCrc16(uint8_t* data, uint16_t len) {
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= data[i] << 8;
        for (uint8_t j = 0; j < 8; j++) {
            crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : (crc << 1);
        }
    }
    return crc;
}

static void uartWriteFrame(HardwareSerial& ser, uint8_t moduleId,
                           uint8_t cmd, const uint8_t* payload, uint16_t len) {
    uint8_t msg[UART_HEADER_SIZE + 2 + 512];
    msg[0] = UART_HDR1;
    msg[1] = UART_HDR2;
    msg[2] = moduleId;
    msg[3] = cmd;
    msg[4] = (len >> 8) & 0xFF;
    msg[5] = len & 0xFF;
    for (uint16_t i = 0; i < len; i++) msg[UART_HEADER_SIZE + i] = payload[i];

    uint16_t c = uartCrc16(msg, UART_HEADER_SIZE + len);
    msg[UART_HEADER_SIZE + len] = (c >> 8) & 0xFF;
    msg[UART_HEADER_SIZE + len + 1] = c & 0xFF;
    ser.write(msg, UART_HEADER_SIZE + len + UART_CRC_SIZE);
}

#endif
