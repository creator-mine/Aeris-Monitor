#ifndef SENSOR_MODULE_H
#define SENSOR_MODULE_H

#include <Arduino.h>
#include <vector>
#include <Wire.h>

// Reads a single register byte over I2C without CRC handling. Drivers whose
// chip shares an address range with another chip (BME680/BMP280 on 0x76/0x77)
// must verify the chip id in detect() instead of trusting an ACK, otherwise the
// first registered driver claims the address.
inline bool readSensorRegister(uint8_t address, uint8_t reg, uint8_t& value) {
    Wire.beginTransmission(address);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom((int)address, (size_t)1) != 1) return false;
    value = Wire.read();
    return true;
}

struct MetricDef {
    const char* key;
    const char* name;
    const char* unit;
};

struct Metric {
    const char* key;
    float value;
    const char* unit;
};

class SensorModule {
    friend class SensorRegistry;
public:
    virtual ~SensorModule() = default;

    virtual uint8_t typeId() const = 0;
    virtual const char* moduleName() const = 0;
    virtual std::vector<uint8_t> i2cAddresses() const = 0;
    virtual bool detect(uint8_t address) = 0;
    virtual bool init(uint8_t address) = 0;
    // Optional background work the driver must do between reads (BSEC has to
    // be serviced every few milliseconds, not once per read interval). Called
    // from the registry poll for every online module, on the loop task and
    // under the Wire lock. Must return quickly.
    virtual void service() {}
    virtual std::vector<Metric> read() = 0;
    virtual std::vector<MetricDef> metrics() const = 0;
    virtual uint32_t readInterval() const = 0;

    // The registry keeps one prototype per driver and clones it once per
    // detected address, so two identical devices on different addresses do
    // not share mutable driver state (current address, handles, calibration).
    // Implementations must return a freshly constructed, not yet initialised
    // instance: never copy an already initialised driver.
    virtual SensorModule* clone() const = 0;

    uint8_t address() const { return _address; }
    bool isActive() const { return _active; }

protected:
    uint8_t _address = 0;
    bool _active = false;
};

#endif