#ifndef SENSOR_REGISTRY_H
#define SENSOR_REGISTRY_H

#include <Arduino.h>
#include <vector>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "sensor_module.h"

#define SENSOR_MUX_CHANNEL_COUNT 8
#define SENSOR_MIN_READ_INTERVAL_MS 500
#define SENSOR_LIVENESS_INTERVAL_MS 10000

// One sensor found on the bus.
//
// The registry owns a private driver clone per detected device, so two identical
// sensors on different addresses (or on different mux channels) never share
// mutable driver state such as the current I2C address.
struct ActiveModule {
    SensorModule* driver = nullptr; // owned by the registry
    uint8_t address = 0;
    uint8_t muxAddress = 0;  // 0 = direct bus, 0x70..0x77 = behind a mux
    uint8_t muxChannel = 0;  // valid only when muxAddress != 0
    unsigned long lastSeen = 0;  // millis() of the last successful bus response
    unsigned long lastRead = 0;  // millis() of the last successful read()
    unsigned long nextReadAt = 0;
    unsigned long scanToken = 0;
    bool online = false;
    std::vector<Metric> cached;
};

// Stable identifier used as the JSON key in /api/v1/sensors and as the
// "id" field in /api/v1/modules. Muxed devices carry a channel suffix so that
// the same device type at the same address on two channels stays unique.
inline String activeModuleId(const ActiveModule& rec) {
    String id = String(rec.driver->moduleName()) + "_0x" + String(rec.address, HEX);
    if (rec.muxAddress != 0) id += "_c" + String(rec.muxChannel);
    return id;
}

class SensorRegistry {
public:
    static SensorRegistry& instance();

    // lock()/unlock() serialize every Wire-bus transaction and every mutation
    // of the module list. Wire is not re-entrant and the HTTP/WebSocket tasks
    // run on the AsyncTCP task, not on the Arduino loop task.
    void lock();
    void unlock();

    void registerDriver(SensorModule* driver);
    void setMuxAddresses(const uint8_t* addresses, size_t count);
    void scanI2CBus(int sda, int scl);
    void checkLiveness();
    void poll();
    void forceRead();

    // BSEC has to be serviced on its own 3 s schedule, but the main loop can
    // block for seconds on TLS/HTTP. Call this once after the first scan to
    // move service() into a dedicated FreeRTOS task; poll() then stops
    // servicing drivers itself.
    void startServiceTask(uint32_t stackSize = 8192, UBaseType_t priority = 2);

    size_t activeCount();
    unsigned long compositionRevision();

    // Snapshot copies: safe to iterate after unlock() returns.
    std::vector<SensorModule*> activeModules();
    std::vector<ActiveModule> activeRecords();

    String modulesToJson();
    String sensorsToJson();

private:
    SensorRegistry();
    ~SensorRegistry();
    SensorRegistry(const SensorRegistry&) = delete;
    SensorRegistry& operator=(const SensorRegistry&) = delete;

    void ensureDrivers();
    void scanBus(uint8_t muxAddress, uint8_t muxChannel);
    bool selectChannel(uint8_t muxAddress, uint8_t muxChannel);
    bool probe(uint8_t muxAddress, uint8_t muxChannel, uint8_t address);
    bool addActive(SensorModule* prototype, uint8_t addr, uint8_t muxAddress,
                   uint8_t muxChannel);
    void readModule(ActiveModule& rec);
    void serviceModules();
    static void serviceTask(void* arg);
    bool recover(ActiveModule& rec);
    ActiveModule* findRecord(SensorModule* driver, uint8_t address,
                             uint8_t muxAddress, uint8_t muxChannel);
    SensorModule* findPrototype(uint8_t typeId);
    static bool due(unsigned long now, unsigned long deadline) {
        return deadline == 0 || static_cast<int32_t>(now - deadline) >= 0;
    }

    std::vector<SensorModule*> _drivers; // prototypes, never activated
    bool _driversBuilt = false;
    std::vector<uint8_t> _muxAddresses;
    std::vector<ActiveModule> _active; // owned clones, online and offline
    unsigned long _lastLiveness = 0;
    unsigned long _scanToken = 1;
    unsigned long _revision = 0; // bumped whenever the module set changes
    bool _serviceTaskRunning = false;
    SemaphoreHandle_t _sem = nullptr;
};

// Driver constructors run on the first bus scan instead of during static
// initialisation: no mutex, no logging, no Wire before setup() has finished.
typedef SensorModule* (*SensorDriverFactory)();
void registerSensorDriverFactory(SensorDriverFactory factory);

// Place at the end of a driver .cpp: that file then self-registers, and adding
// a sensor never requires touching setup().
#define REGISTER_SENSOR(ModuleClass)                                          \
    namespace {                                                               \
    const bool _sensor_registered_##ModuleClass =                              \
        (registerSensorDriverFactory(                                         \
             []() -> SensorModule* { return new ModuleClass(); }),            \
         true);                                                               \
    }

#endif