#ifndef UART_FRAME_H
#define UART_FRAME_H

#include <Arduino.h>
#include "uart_protocol.h"

// Resync-aware UART frame parser. Feed bytes one at a time; whenever a
// complete, CRC-valid frame is available the handler is invoked with the
// decoded module id / command / payload. The internal buffer is a small
// rolling buffer, so a corrupted/truncated frame never wedges the parser:
// on a header mismatch the first byte is dropped and parsing continues
// (classic 0xAA 0x55 prefix resync).
//
// Frames larger than UART_BUFFER_SIZE are treated as invalid and skipped
// byte-by-byte until the next valid header.
typedef void (*uartFrameHandler)(uint8_t moduleId, uint8_t cmd,
                                 uint8_t* payload, uint16_t payloadLen,
                                 void* context);

class UartFrameParser {
public:
    UartFrameParser() : _len(0) {}

    void feed(uint8_t b, uartFrameHandler handler, void* context) {
        if (_len < UART_BUFFER_SIZE) _buf[_len++] = b;

        // Process as many complete frames as are present in the buffer.
        for (;;) {
            if (_len < UART_HEADER_SIZE + UART_CRC_SIZE) return;

            // Header mismatch -> drop one byte and re-scan.
            if (_buf[0] != UART_HDR1 || _buf[1] != UART_HDR2) {
                drop(1);
                continue;
            }

            uint16_t payloadLen = ((uint16_t)_buf[4] << 8) | _buf[5];
            uint32_t total = UART_HEADER_SIZE + (uint32_t)payloadLen + UART_CRC_SIZE;

            if (total > UART_BUFFER_SIZE) {
                // Corrupt length field (or too-big frame): resync.
                drop(1);
                continue;
            }
            if (_len < total) return; // waiting for the rest of the frame

            uint16_t rxCrc = ((uint16_t)_buf[total - 2] << 8) | _buf[total - 1];
            uint16_t calcCrc = uartCrc16(_buf, total - 2);
            if (rxCrc == calcCrc) {
                if (handler) {
                    handler(_buf[2], _buf[3], _buf + UART_HEADER_SIZE,
                            payloadLen, context);
                }
            }
            drop(total);
        }
    }

    void reset() { _len = 0; }

private:
    uint8_t _buf[UART_BUFFER_SIZE];
    uint16_t _len;

    void drop(uint16_t n) {
        if (n >= _len) {
            _len = 0;
            return;
        }
        memmove(_buf, _buf + n, _len - n);
        _len -= n;
    }
};

#endif