#ifndef BME680_MODULE_H
#define BME680_MODULE_H

#include "sensor_module.h"
#include <bsec2.h>

// BME680/BME688 driven through Bosch BSEC2. The library owns the sensor and
// runs its own 3 s measurement cycle; the driver only forwards the virtual
// outputs to the registry. IAQ is a relative air-quality index (0 clean,
// 500 heavily polluted) and is meaningless without its accuracy flag:
// 0 = warming up, 3 = calibrated. The raw gas resistance is an internal
// input of the algorithm and is deliberately not published as a metric.
class BME680Module : public SensorModule {
public:
    uint8_t typeId() const override { return 1; }
    const char* moduleName() const override { return "BME680"; }
    std::vector<uint8_t> i2cAddresses() const override;
    bool detect(uint8_t address) override;
    bool init(uint8_t address) override;
    void service() override;
    std::vector<Metric> read() override;
    std::vector<MetricDef> metrics() const override;
    uint32_t readInterval() const override { return 3000; }
    SensorModule* clone() const override { return new BME680Module(); }

private:
    void loadState();
    void saveState();
    void captureOutputs(const bsecOutputs& outputs);

    Bsec2 _bsec;
    uint8_t _memBlock[BSEC_INSTANCE_SIZE] = {};
    bool _ready = false;
    bool _stateDirty = false;
    bool _pressureLogged = false;
    float _temperature = NAN;
    float _humidity = NAN;
    float _pressure = NAN;
    float _iaq = NAN;
    float _iaqAccuracy = NAN;
    unsigned long _lastStateSave = 0;
    unsigned long _lastErrorLog = 0;
};

#endif
