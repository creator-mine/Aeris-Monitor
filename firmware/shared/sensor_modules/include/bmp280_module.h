#ifndef BMP280_MODULE_H
#define BMP280_MODULE_H

#include "sensor_module.h"
#include <Adafruit_BMP280.h>

// Pressure and temperature. More accurate for pressure than the BME680 and
// cheaper, but shares the 0x76/0x77 addresses with it, so detect() checks the
// chip id instead of trusting an ACK.
class BMP280Module : public SensorModule {
public:
    uint8_t typeId() const override { return 5; }
    const char* moduleName() const override { return "BMP280"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 5000; }
    SensorModule* clone() const override { return new BMP280Module(); }

private:
    Adafruit_BMP280 _bmp;
    bool _bmpReady = false;
};

#endif