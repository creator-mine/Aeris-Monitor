#ifndef INA219_MODULE_H
#define INA219_MODULE_H

#include "sensor_module.h"
#include <Adafruit_INA219.h>

// Bus voltage, current and power of a supply rail: battery level in a remote
// node, or the input of a sensor module fed over UART.
class INA219Module : public SensorModule {
public:
    uint8_t typeId() const override { return 4; }
    const char* moduleName() const override { return "INA219"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 5000; }
    SensorModule* clone() const override { return new INA219Module(); }

private:
    Adafruit_INA219 _ina;
    bool _inaReady = false;
};

#endif