#include "bme680_module.h"
#include "sensor_registry.h"
#include <Wire.h>
#include <algorithm>

std::vector<uint8_t> BME680Module::i2cAddresses() const {
    return {0x76, 0x77};
}

// BME680 and BMP280 both answer on 0x76/0x77, so an ACK alone is not enough:
// the chip id decides which driver owns the address.
bool BME680Module::detect(uint8_t address) {
    uint8_t chipId = 0;
    if (!readSensorRegister(address, 0xD0, chipId)) return false;
    return chipId == 0x60;
}

bool BME680Module::init(uint8_t address) {
    _address = address;

    if (!_bme.begin(address)) {
        Serial.printf("[BME680] Not found at 0x%02X\n", address);
        return false;
    }

    _bme.setTemperatureOversampling(BME680_OS_8X);
    _bme.setHumidityOversampling(BME680_OS_2X);
    _bme.setPressureOversampling(BME680_OS_4X);
    _bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    _bme.setGasHeater(320, 150);

    _bmeReady = true;
    _active = true;
    Serial.printf("[BME680] Initialized at 0x%02X\n", address);
    return true;
}

std::vector<Metric> BME680Module::read() {
    std::vector<Metric> result;

    if (!_bmeReady) return result;

    unsigned long end = _bme.beginReading();
    if (end == 0 || !_bme.endReading()) return result;

    result.push_back({"temperature", _bme.readTemperature(), "C"});
    result.push_back({"humidity", _bme.readHumidity(), "%"});
    result.push_back({"pressure", _bme.readPressure() / 100.0F, "hPa"});
    result.push_back({"gas_resistance", (float)_bme.gas_resistance, "Ohm"});

    return result;
}

std::vector<MetricDef> BME680Module::metrics() const {
    return {
        {"temperature", "Temperature", "C"},
        {"humidity", "Humidity", "%"},
        {"pressure", "Pressure", "hPa"},
        {"gas_resistance", "Gas Resistance", "Ohm"}
    };
}

REGISTER_SENSOR(BME680Module)