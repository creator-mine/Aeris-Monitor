#include "scd30_module.h"
#include "sensor_registry.h"
#include <Wire.h>

std::vector<uint8_t> SCD30Module::i2cAddresses() const {
    return {0x61};
}

// The SCD30 has no chip id register, so an ACK is the only identification
// available. 0x61 is not shared with any other driver in this project.
bool SCD30Module::detect(uint8_t address) {
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

bool SCD30Module::init(uint8_t address) {
    _address = address;

    // begin() soft-resets the sensor and already starts continuous measurement
    // with a 2 s interval, so only self-calibration is left to configure.
    if (!_scd.begin(address, &Wire)) {
        Serial.printf("[SCD30] Not found at 0x%02X\n", address);
        return false;
    }

    // Sensirion's automatic self-calibration assumes 400 ppm fresh air, which
    // only holds in ventilated air. In a closed enclosure it drags the reading
    // down towards ambient CO2 - turn it off if the module sits in a box.
    _scd.selfCalibrationEnabled(true);

    _scdReady = true;
    _active = true;
    Serial.printf("[SCD30] Initialized at 0x%02X\n", address);
    return true;
}

std::vector<Metric> SCD30Module::read() {
    std::vector<Metric> result;

    if (!_scdReady) return result;

    // dataReady() stays false until the first sample is ready, which takes
    // about 15 s after power-up.
    if (!_scd.dataReady()) return result;
    if (!_scd.read()) return result;

    result.push_back({"scd30_co2", _scd.CO2, "ppm"});
    result.push_back({"scd30_temperature", _scd.temperature, "C"});
    result.push_back({"scd30_humidity", _scd.relative_humidity, "%"});

    return result;
}

std::vector<MetricDef> SCD30Module::metrics() const {
    return {
        {"scd30_co2", "CO2", "ppm"},
        {"scd30_temperature", "Temperature", "C"},
        {"scd30_humidity", "Humidity", "%"}
    };
}

REGISTER_SENSOR(SCD30Module)