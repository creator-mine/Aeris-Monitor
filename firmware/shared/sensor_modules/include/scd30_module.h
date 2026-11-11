#ifndef SCD30_MODULE_H
#define SCD30_MODULE_H

#include "sensor_module.h"
#include <Adafruit_SCD30.h>

// CO2, temperature and humidity. Temperature and humidity overlap with the
// BME680, so every metric key carries the type prefix: the controller turns the
// key into an MQTT topic (iot/<device>/sensors/<key>) and an SD log column, and
// unprefixed keys would make two modules publish to the same topic.
class SCD30Module : public SensorModule {
public:
    uint8_t typeId() const override { return 3; }
    const char* moduleName() const override { return "SCD30"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 2000; }
    SensorModule* clone() const override { return new SCD30Module(); }

private:
    Adafruit_SCD30 _scd;
    bool _scdReady = false;
};

#endif