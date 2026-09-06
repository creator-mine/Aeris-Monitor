#ifndef BH1750_MODULE_H
#define BH1750_MODULE_H

#include "sensor_module.h"
#include <BH1750.h>

class BH1750Module : public SensorModule {
public:
    uint8_t typeId() const override { return 2; }
    const char* moduleName() const override { return "BH1750"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 5000; }

private:
    BH1750 _bh1750;
    bool _bhReady = false;
    uint8_t _detectedAddr = 0;
};

#endif
