#ifndef SENSOR_REGISTRY_H
#define SENSOR_REGISTRY_H

#include <Arduino.h>
#include <vector>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "sensor_module.h"

class SensorRegistry {
public:
    static SensorRegistry& instance();

    // lock()/unlock() serialize every Wire-bus transaction and every mutation
    // of the active-module list. The loop task calls lock() around sensorsRead()
    // so it never overlaps scanI2CBus / sensorsToJson() / checkLiveness() from
    // the ESPAsyncWebServer task (Wire is not re-entrant).
    void lock();
    void unlock();

    void registerDriver(SensorModule* driver);
    void scanI2CBus(int sda, int scl);
    void checkLiveness();

    size_t activeCount();
    // Returns a copy of the active module list (safe to iterate after unlock;
    // module objects are owned by the registry and never freed by liveness).
    std::vector<SensorModule*> activeModules();

    String modulesToJson();
    String sensorsToJson();

private:
    SensorRegistry();
    ~SensorRegistry();
    SensorRegistry(const SensorRegistry&) = delete;
    SensorRegistry& operator=(const SensorRegistry&) = delete;

    std::vector<SensorModule*> _drivers;
    std::vector<SensorModule*> _active;
    unsigned long _lastLiveness = 0;
    SemaphoreHandle_t _mux = nullptr;

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
