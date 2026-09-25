#include "modules/sensor_registry.h"
#include "ring_logger.h"
#include <Wire.h>

SensorRegistry& SensorRegistry::instance() {
    static SensorRegistry registry;
    return registry;
}

SensorRegistry::SensorRegistry() {
    _mux = xSemaphoreCreateMutex();
}

SensorRegistry::~SensorRegistry() {
    if (_mux) vSemaphoreDelete(_mux);
    for (auto* d : _drivers) delete d;
    for (auto* a : _active) {
        if (std::find(_drivers.begin(), _drivers.end(), a) == _drivers.end())
            delete a;
    }
}

void SensorRegistry::lock() {
    if (_mux) xSemaphoreTake(_mux, portMAX_DELAY);
}

void SensorRegistry::unlock() {
    if (_mux) xSemaphoreGive(_mux);
}

void SensorRegistry::registerDriver(SensorModule* driver) {
    lock();
    _drivers.push_back(driver);
    Serial.printf("[Registry] Driver registered: %s (type %d)\n",
                  driver->moduleName(), driver->typeId());
    unlock();
}

void SensorRegistry::scanI2CBus(int sda, int scl) {
    lock();

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
                    LOG_INFO("Sensor", "%s detected at 0x%02X",
                             driver->moduleName(), addr);
                    Serial.printf("[Registry] Module detected: %s at 0x%02X\n",
                                  driver->moduleName(), addr);
                }
                break;
            }
        }
    }
    Serial.printf("[Registry] Scan complete. Active modules: %d\n", _active.size());

    unlock();
}

void SensorRegistry::checkLiveness() {
    lock();

    if (millis() - _lastLiveness >= 10000) {
        _lastLiveness = millis();

        for (size_t i = 0; i < _active.size(); ) {
            auto* mod = _active[i];
            Wire.beginTransmission(mod->address());
            if (Wire.endTransmission() != 0) {
                LOG_INFO("Sensor", "Module lost: %s at 0x%02X",
                         mod->moduleName(), mod->address());
                Serial.printf("[Registry] Module lost: %s at 0x%02X\n",
                              mod->moduleName(), mod->address());
                _active.erase(_active.begin() + i);
            } else {
                i++;
            }
        }
    }

    unlock();
}

void SensorRegistry::addActive(SensorModule* mod, uint8_t addr) {
    for (auto* a : _active) {
        if (a->typeId() == mod->typeId() && a->address() == addr) return;
    }
    mod->_address = addr;
    mod->_active = true;
    _active.push_back(mod);
}

size_t SensorRegistry::activeCount() {
    lock();
    size_t n = _active.size();
    unlock();
    return n;
}

std::vector<SensorModule*> SensorRegistry::activeModules() {
    lock();
    std::vector<SensorModule*> copy = _active;
    unlock();
    return copy;
}

static void indentComma(String& json, bool& first) {
    if (!first) json += ',';
    first = false;
}

String SensorRegistry::modulesToJson() {
    lock();

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

    unlock();
    return json;
}

String SensorRegistry::sensorsToJson() {
    lock();

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

    unlock();
    return json;
}