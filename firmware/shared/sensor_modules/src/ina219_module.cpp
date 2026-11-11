#include "ina219_module.h"
#include "sensor_registry.h"
#include <Wire.h>

std::vector<uint8_t> INA219Module::i2cAddresses() const {
    return {0x40};
}

// The INA219 exposes no identification register; 0x40 is the only address the
// part answers to unless A0/A1 are tied high (0x41).
bool INA219Module::detect(uint8_t address) {
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

bool INA219Module::init(uint8_t address) {
    _address = address;

    // Adafruit_INA219 1.2.x keeps its I2C address private and begin() takes no
    // address argument, so only the library default 0x40 can be driven here.
    if (address != INA219_ADDRESS) {
        Serial.printf("[INA219] Address 0x%02X unsupported by the library\n",
                      address);
        return false;
    }

    if (!_ina.begin(&Wire)) {
        Serial.printf("[INA219] Not found at 0x%02X\n", address);
        return false;
    }

    _ina.setCalibration_32V_2A();

    _inaReady = true;
    _active = true;
    Serial.printf("[INA219] Initialized at 0x%02X\n", address);
    return true;
}

std::vector<Metric> INA219Module::read() {
    std::vector<Metric> result;

    if (!_inaReady) return result;

    result.push_back({"ina219_voltage", _ina.getBusVoltage_V(), "V"});
    result.push_back({"ina219_current", _ina.getCurrent_mA(), "mA"});
    result.push_back({"ina219_power", _ina.getPower_mW(), "mW"});

    return result;
}

std::vector<MetricDef> INA219Module::metrics() const {
    return {
        {"ina219_voltage", "Bus Voltage", "V"},
        {"ina219_current", "Current", "mA"},
        {"ina219_power", "Power", "mW"}
    };
}

REGISTER_SENSOR(INA219Module)