#ifndef SENSOR_REGISTRY_H
#define SENSOR_REGISTRY_H

#include <Arduino.h>
#include <vector>
#include "sensor_module.h"

class SensorRegistry {
public:
    static SensorRegistry& instance();

    void registerDriver(SensorModule* driver);
    void scanI2CBus(int sda, int scl);
    void checkLiveness();

    size_t activeCount() const { return _active.size(); }
    const std::vector<SensorModule*>& activeModules() const { return _active; }

    String modulesToJson() const;
    String sensorsToJson() const;

private:
    SensorRegistry() = default;
    ~SensorRegistry();
    SensorRegistry(const SensorRegistry&) = delete;
    SensorRegistry& operator=(const SensorRegistry&) = delete;

    std::vector<SensorModule*> _drivers;
    std::vector<SensorModule*> _active;
    unsigned long _lastLiveness = 0;

    void addActive(SensorModule* mod, uint8_t addr);
};

#define REGISTER_SENSOR(ModuleClass) \
    static SensorRegistrar _reg_##ModuleClass( \
        []() { SensorRegistry::instance().registerDriver(new ModuleClass()); } \
    );

class SensorRegistrar {
public:
    SensorRegistrar(void (*reg)()) { reg(); }
};

#endif
