#include "bmp280_module.h"
#include "sensor_registry.h"
#include <Wire.h>

std::vector<uint8_t> BMP280Module::i2cAddresses() const {
    return {0x76, 0x77};
}

// The BME680 occupies the same two addresses and answers to a plain ACK, so the
// chip id decides which driver owns the address. Without this check the first
// registered driver would silently take the sensor from the other.
bool BMP280Module::detect(uint8_t address) {
    uint8_t chipId = 0;
    if (!readSensorRegister(address, 0xD0, chipId)) return false;
    return chipId == 0x58;
}

bool BMP280Module::init(uint8_t address) {
    _address = address;

    // begin() verifies the chip id internally, so a BME680 on this address
    // fails here even if detect() were bypassed.
    if (!_bmp.begin(address)) {
        Serial.printf("[BMP280] Not found at 0x%02X\n", address);
        return false;
    }

    _bmp.setSampling(Adafruit_BMP280::MODE_NORMAL,
                     Adafruit_BMP280::SAMPLING_X2,
                     Adafruit_BMP280::SAMPLING_X16,
                     Adafruit_BMP280::FILTER_X4,
                     Adafruit_BMP280::STANDBY_MS_1);

    _bmpReady = true;
    _active = true;
    Serial.printf("[BMP280] Initialized at 0x%02X\n", address);
    return true;
}

std::vector<Metric> BMP280Module::read() {
    std::vector<Metric> result;

    if (!_bmpReady) return result;

    result.push_back({"bmp280_temperature", _bmp.readTemperature(), "C"});
    result.push_back({"bmp280_pressure", _bmp.readPressure() / 100.0F, "hPa"});

    return result;
}

std::vector<MetricDef> BMP280Module::metrics() const {
    return {
        {"bmp280_temperature", "Temperature", "C"},
        {"bmp280_pressure", "Pressure", "hPa"}
    };
}

REGISTER_SENSOR(BMP280Module)