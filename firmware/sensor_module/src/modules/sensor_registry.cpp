#include "modules/sensor_registry.h"
#include <Wire.h>

SensorRegistry& SensorRegistry::instance() {
    static SensorRegistry registry;
    return registry;
}

SensorRegistry::~SensorRegistry() {
    for (auto* d : _drivers) delete d;
    for (auto* a : _active) {
        if (std::find(_drivers.begin(), _drivers.end(), a) == _drivers.end())
            delete a;
    }
}

void SensorRegistry::registerDriver(SensorModule* driver) {
    _drivers.push_back(driver);
    Serial.printf("[Registry] Driver registered: %s (type %d)\n",
                  driver->moduleName(), driver->typeId());
}

void SensorRegistry::scanI2CBus(int sda, int scl) {
    Wire.begin(sda, scl);
    Serial.println("[Registry] Scanning I2C bus...");

    for (uint8_t addr = 1; addr < 127; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() != 0) continue;

        Serial.printf("[Registry] I2C device found at 0x%02X\n", addr);

        for (auto* driver : _drivers) {
            auto addrs = driver->i2cAddresses();
            if (std::find(addrs.begin(), addrs.end(), addr) == addrs.end())
                continue;

            if (driver->detect(addr)) {
                if (driver->init(addr)) {
                    addActive(driver, addr);
                    Serial.printf("[Registry] Module detected: %s at 0x%02X\n",
                                  driver->moduleName(), addr);
                }
                break;
            }
        }
    }
    Serial.printf("[Registry] Scan complete. Active modules: %d\n", _active.size());
}

void SensorRegistry::checkLiveness() {
    if (millis() - _lastLiveness < 10000) return;
    _lastLiveness = millis();

    for (size_t i = 0; i < _active.size(); ) {
        auto* mod = _active[i];
        Wire.beginTransmission(mod->address());
        if (Wire.endTransmission() != 0) {
            Serial.printf("[Registry] Module lost: %s at 0x%02X\n",
                          mod->moduleName(), mod->address());
            _active.erase(_active.begin() + i);
        } else {
            i++;
        }
    }
}

void SensorRegistry::addActive(SensorModule* mod, uint8_t addr) {
    for (auto* a : _active) {
        if (a->typeId() == mod->typeId() && a->address() == addr) return;
    }
    mod->_address = addr;
    mod->_active = true;
    _active.push_back(mod);
}

static void indentComma(String& json, bool& first) {
    if (!first) json += ',';
    first = false;
}

String SensorRegistry::modulesToJson() const {
    String json = "[";
    bool first = true;

    for (auto* mod : _active) {
        indentComma(json, first);
        json += "{";
        json += "\"id\":\"" + String(mod->moduleName()) + "_0x" + String(mod->address(), HEX) + "\",";
        json += "\"type_id\":" + String(mod->typeId()) + ",";
        json += "\"name\":\"" + String(mod->moduleName()) + "\",";
        json += "\"status\":\"online\",";
        json += "\"address\":\"0x" + String(mod->address(), HEX) + "\",";

        auto mdefs = mod->metrics();
        json += "\"metrics\":[";
        bool mfirst = true;
        for (auto& m : mdefs) {
            indentComma(json, mfirst);
            json += "{";
            json += "\"key\":\"" + String(m.key) + "\",";
            json += "\"name\":\"" + String(m.name) + "\",";
            json += "\"unit\":\"" + String(m.unit) + "\"";
            json += "}";
        }
        json += "]}";
    }

    json += "]";
    return json;
}

String SensorRegistry::sensorsToJson() const {
    String json = "{";
    json += "\"timestamp\":" + String(millis()) + ",";
    json += "\"modules\":{";
    bool first = true;

    for (auto* mod : _active) {
        indentComma(json, first);
        String modId = String(mod->moduleName()) + "_0x" + String(mod->address(), HEX);
        json += "\"" + modId + "\":{";

        auto metrics = mod->read();
        bool mfirst = true;
        for (auto& m : metrics) {
            indentComma(json, mfirst);
            json += "\"" + String(m.key) + "\":" + String(m.value, 2);
        }
        json += "}";
    }

    json += "}}";
    return json;
}
