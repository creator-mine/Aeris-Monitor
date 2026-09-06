#ifndef BME680_MODULE_H
#define BME680_MODULE_H

#include "sensor_module.h"
#include <Adafruit_BME680.h>

class BME680Module : public SensorModule {
public:
    uint8_t typeId() const override { return 1; }
    const char* moduleName() const override { return "BME680"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 5000; }

private:
    Adafruit_BME680 _bme;
    bool _bmeReady = false;
};

#endif
