#ifndef SENSOR_MODULE_H
#define SENSOR_MODULE_H

#include <Arduino.h>
#include <vector>

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
    virtual std::vector<Metric> read() = 0;
    virtual std::vector<MetricDef> metrics() const = 0;
    virtual uint32_t readInterval() const = 0;

    uint8_t address() const { return _address; }
    bool isActive() const { return _active; }

protected:
    uint8_t _address = 0;
    bool _active = false;
};

#endif
