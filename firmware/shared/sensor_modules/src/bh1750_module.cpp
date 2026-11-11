#include "bh1750_module.h"
#include "sensor_registry.h"
#include <Wire.h>

std::vector<uint8_t> BH1750Module::i2cAddresses() const {
    return {0x23, 0x5C};
}

bool BH1750Module::detect(uint8_t address) {
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

bool BH1750Module::init(uint8_t address) {
    if (!_bh1750.begin(BH1750::CONTINUOUS_HIGH_RES_MODE, (byte)address)) {
        Serial.printf("[BH1750] Init failed at 0x%02X\n", address);
        return false;
    }

    _address = address;
    _bhReady = true;
    _active = true;
    Serial.printf("[BH1750] Initialized at 0x%02X\n", address);
    return true;
}

std::vector<Metric> BH1750Module::read() {
    std::vector<Metric> result;

    if (!_bhReady) return result;

    float lux = _bh1750.readLightLevel();
    // The library returns -1 on a failed I2C read and -2 when the sensor was
    // never configured; neither is a measurement.
    if (!(lux >= 0.0F)) return result;

    result.push_back({"illuminance", lux, "lux"});

    return result;
}

std::vector<MetricDef> BH1750Module::metrics() const {
    return {
        {"illuminance", "Illuminance", "lux"}
    };
}

REGISTER_SENSOR(BH1750Module)