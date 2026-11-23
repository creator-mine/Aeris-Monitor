#include "sensor_registry.h"
#include <Wire.h>
#include <algorithm>
#include <cmath>
#include <cstring>

#if __has_include("ring_logger.h")
#include "ring_logger.h"
#define SENSOR_LOG(...) LOG_INFO("Sensor", __VA_ARGS__)
#else
#define SENSOR_LOG(...) ((void)0)
#endif

namespace {

std::vector<SensorDriverFactory>& driverFactories() {
    static std::vector<SensorDriverFactory> factories;
    return factories;
}

void indentComma(String& json, bool& first) {
    if (!first) json += ',';
    first = false;
}

// A driver can report fewer values than metrics() declares: the SCD30 has no
// sample for the first ~15 s and every driver returns nothing when a read fails.
// The cache is therefore rebuilt in the declared order with exactly one entry
// per metric and NAN for values that are not available yet. That keeps the
// UART data frame, /api/v1/sensors and CMD_REGISTER in agreement on key order
// and count, and every consumer skips non-finite values.
void mergeCache(ActiveModule& rec, const std::vector<Metric>& values) {
    auto defs = rec.driver->metrics();
    std::vector<Metric> merged;
    merged.reserve(defs.size());

    for (const auto& def : defs) {
        float value = NAN;
        for (const auto& m : values) {
            if (strcmp(m.key, def.key) == 0) {
                value = m.value;
                break;
            }
        }
        if (!std::isfinite(value)) {
            // Keep the last good reading instead of a hole in the stream.
            for (const auto& old : rec.cached) {
                if (strcmp(old.key, def.key) == 0) {
                    value = old.value;
                    break;
                }
            }
        }
        merged.push_back({def.key, value, def.unit});
    }

    rec.cached.swap(merged);
}

} // namespace

void registerSensorDriverFactory(SensorDriverFactory factory) {
    if (factory) driverFactories().push_back(factory);
}

SensorRegistry& SensorRegistry::instance() {
    static SensorRegistry registry;
    return registry;
}

SensorRegistry::SensorRegistry() {
    _sem = xSemaphoreCreateMutex();
}

SensorRegistry::~SensorRegistry() {
    for (auto& rec : _active) delete rec.driver;
    for (auto* d : _drivers) delete d;
    if (_sem) vSemaphoreDelete(_sem);
}

void SensorRegistry::lock() {
    if (_sem) xSemaphoreTake(_sem, portMAX_DELAY);
}

void SensorRegistry::unlock() {
    if (_sem) xSemaphoreGive(_sem);
}

void SensorRegistry::registerDriver(SensorModule* driver) {
    if (!driver) return;
    lock();
    _drivers.push_back(driver);
    Serial.printf("[Registry] Driver registered: %s (type %d)\n",
                  driver->moduleName(), driver->typeId());
    unlock();
}

void SensorRegistry::setMuxAddresses(const uint8_t* addresses, size_t count) {
    lock();
    _muxAddresses.clear();
    for (size_t i = 0; i < count; i++) {
        if (addresses[i] != 0) _muxAddresses.push_back(addresses[i]);
    }
    Serial.printf("[Registry] I2C mux addresses configured: %d\n",
                  (int)_muxAddresses.size());
    unlock();
}

// Prototypes are built on the first scan, not during static initialisation.
void SensorRegistry::ensureDrivers() {
    if (_driversBuilt) return;
    _driversBuilt = true;
    for (auto factory : driverFactories()) {
        SensorModule* proto = factory();
        if (!proto) continue;
        bool duplicate = false;
        for (auto* existing : _drivers) {
            if (existing->typeId() == proto->typeId()) duplicate = true;
        }
        if (duplicate) {
            delete proto;
            continue;
        }
        _drivers.push_back(proto);
        Serial.printf("[Registry] Driver registered: %s (type %d)\n",
                      proto->moduleName(), proto->typeId());
    }
}

bool SensorRegistry::selectChannel(uint8_t muxAddress, uint8_t muxChannel) {
    if (muxAddress == 0) return true;
    if (muxChannel >= SENSOR_MUX_CHANNEL_COUNT) return false;
    Wire.beginTransmission(muxAddress);
    Wire.write((uint8_t)(1u << muxChannel));
    return Wire.endTransmission() == 0;
}

bool SensorRegistry::probe(uint8_t muxAddress, uint8_t muxChannel,
                           uint8_t address) {
    if (!selectChannel(muxAddress, muxChannel)) return false;
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

ActiveModule* SensorRegistry::findRecord(SensorModule* driver, uint8_t address,
                                        uint8_t muxAddress, uint8_t muxChannel) {
    // The mux channel is part of the identity: two identical sensors answering on
    // the same address on two channels are two devices, not one.
    for (auto& rec : _active) {
        if (rec.driver->typeId() == driver->typeId() &&
            rec.address == address && rec.muxAddress == muxAddress &&
            rec.muxChannel == muxChannel)
            return &rec;
    }
    return nullptr;
}

SensorModule* SensorRegistry::findPrototype(uint8_t typeId) {
    for (auto* driver : _drivers) {
        if (driver->typeId() == typeId) return driver;
    }
    return nullptr;
}

void SensorRegistry::scanBus(uint8_t muxAddress, uint8_t muxChannel) {
    if (!selectChannel(muxAddress, muxChannel)) {
        Serial.printf("[Registry] Mux 0x%02X channel %u not responding\n",
                      muxAddress, muxChannel);
        return;
    }

    for (uint8_t addr = 1; addr < 127; addr++) {
        // Do not probe a configured multiplexer as if it were a sensor: a
        // zero-length write to a TCA9548A can change its channel register.
        // Only the main bus can hold the mux, so channels are scanned in full.
        // Never skip 0x70..0x77 as a range: BME680 and BMP280 use 0x76/0x77.
        if (muxAddress == 0 &&
            std::find(_muxAddresses.begin(), _muxAddresses.end(), addr) !=
                _muxAddresses.end()) {
            continue;
        }

        Wire.beginTransmission(addr);
        if (Wire.endTransmission() != 0) continue;
        Serial.printf("[Registry] I2C ACK 0x%02X\n", addr);

        for (auto* driver : _drivers) {
            auto addrs = driver->i2cAddresses();
            if (std::find(addrs.begin(), addrs.end(), addr) == addrs.end())
                continue;

            if (!driver->detect(addr)) continue;
            if (addActive(driver, addr, muxAddress, muxChannel)) {
                ActiveModule* rec =
                    findRecord(driver, addr, muxAddress, muxChannel);
                if (rec) rec->scanToken = _scanToken;
                break; // the driver that initialised this address owns it
            }
            // init() failed: let the next driver try the same address
        }
    }
}

bool SensorRegistry::addActive(SensorModule* prototype, uint8_t addr,
                               uint8_t muxAddress, uint8_t muxChannel) {
    ActiveModule* existing =
        findRecord(prototype, addr, muxAddress, muxChannel);
    if (existing) {
        // Same sensor found again: revive it, do not create a second driver.
        existing->muxAddress = muxAddress;
        existing->muxChannel = muxChannel;
        if (existing->online) return true;
        if (!recover(*existing)) return false;
        Serial.printf("[Registry] Module recovered: %s at 0x%02X\n",
                      existing->driver->moduleName(), addr);
        return true;
    }

    SensorModule* instance = prototype->clone();
    if (!instance) return false;

    if (!instance->init(addr)) {
        delete instance;
        return false;
    }

    ActiveModule rec;
    rec.driver = instance;
    rec.address = addr;
    rec.muxAddress = muxAddress;
    rec.muxChannel = muxChannel;
    rec.lastSeen = millis();
    rec.scanToken = _scanToken;
    rec.online = true;
    rec.nextReadAt = 0;
    _active.push_back(rec);
    _revision++;

    Serial.printf("[Registry] Module detected: %s at 0x%02X%s\n",
                  instance->moduleName(), addr,
                  muxAddress ? (String("_c") + String(muxChannel)).c_str() : "");
    SENSOR_LOG("%s detected at 0x%02X", instance->moduleName(), addr);
    return true;
}

void SensorRegistry::scanI2CBus(int sda, int scl) {
    lock();

    Wire.begin(sda, scl);
    ensureDrivers();

    Serial.printf("[Registry] Scanning I2C bus (SDA=%d SCL=%d)...\n", sda, scl);
    _scanToken++;

    scanBus(0, 0);
    for (uint8_t mux : _muxAddresses) {
        for (uint8_t ch = 0; ch < SENSOR_MUX_CHANNEL_COUNT; ch++) {
            scanBus(mux, ch);
        }
    }

    size_t online = 0;
    for (auto& rec : _active) {
        if (rec.scanToken == _scanToken) {
            rec.online = true;
            rec.lastSeen = millis();
            online++;
            continue;
        }
        if (rec.online) {
            rec.online = false;
            Serial.printf("[Registry] Module lost: %s at 0x%02X\n",
                          rec.driver->moduleName(), rec.address);
            SENSOR_LOG("Module lost: %s at 0x%02X", rec.driver->moduleName(),
                       rec.address);
            _revision++;
        }
    }

    Serial.printf("[Registry] Scan complete: %d online, %d known\n",
                  (int)online, (int)_active.size());
    unlock();
}

void SensorRegistry::checkLiveness() {
    lock();

    if (millis() - _lastLiveness >= SENSOR_LIVENESS_INTERVAL_MS) {
        _lastLiveness = millis();
        unsigned long now = millis();

        for (auto& rec : _active) {
            if (!probe(rec.muxAddress, rec.muxChannel, rec.address)) {
                if (rec.online) {
                    rec.online = false;
                    Serial.printf("[Registry] Module lost: %s at 0x%02X\n",
                                  rec.driver->moduleName(), rec.address);
                    SENSOR_LOG("Module lost: %s at 0x%02X",
                               rec.driver->moduleName(), rec.address);
                    _revision++;
                }
                continue;
            }

            rec.lastSeen = now;
            if (rec.online) continue;

            if (recover(rec)) {
                Serial.printf("[Registry] Module recovered: %s at 0x%02X\n",
                              rec.driver->moduleName(), rec.address);
            }
        }
    }

    unlock();
}

// Brings an offline record back with a fresh driver instance. Re-running
// init() on the old instance would trust stale handles, and Adafruit_SCD30 /
// Adafruit_BMP280 allocate helper objects on every begin() without freeing the
// previous ones, so a clone is cheaper than a leak per power cycle.
bool SensorRegistry::recover(ActiveModule& rec) {
    SensorModule* prototype = findPrototype(rec.driver->typeId());
    if (prototype == nullptr || !prototype->detect(rec.address)) return false;

    SensorModule* fresh = prototype->clone();
    if (fresh == nullptr) return false;
    if (!fresh->init(rec.address)) {
        delete fresh;
        return false;
    }

    delete rec.driver;
    rec.driver = fresh;
    rec.lastRead = 0;
    rec.nextReadAt = 0;
    rec.online = true;
    _revision++;
    return true;
}

void SensorRegistry::readModule(ActiveModule& rec) {
    if (!selectChannel(rec.muxAddress, rec.muxChannel)) return;

    auto values = rec.driver->read();
    mergeCache(rec, values);

    // A driver that has nothing to report yet (SCD30 warming up) leaves only
    // NAN behind, which counts as no successful read.
    for (const auto& m : rec.cached) {
        if (std::isfinite(m.value)) {
            rec.lastRead = millis();
            break;
        }
    }
}

void SensorRegistry::serviceModules() {
    lock();
    for (auto& rec : _active) {
        if (!rec.online) continue;
        if (!selectChannel(rec.muxAddress, rec.muxChannel)) continue;
        rec.driver->service();
    }
    unlock();
}

void SensorRegistry::serviceTask(void* arg) {
    SensorRegistry* self = static_cast<SensorRegistry*>(arg);
    for (;;) {
        self->serviceModules();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

void SensorRegistry::startServiceTask(uint32_t stackSize, UBaseType_t priority) {
    if (_serviceTaskRunning) return;
    // Set the flag before the task exists: poll() must stop servicing first,
    // otherwise both would step the same BSEC state (the mutex serialises the
    // bus, not the algorithm).
    _serviceTaskRunning = true;
    if (xTaskCreate(&SensorRegistry::serviceTask, "sensor_svc", stackSize, this,
                    priority, nullptr) != pdPASS) {
        _serviceTaskRunning = false;
        Serial.println("[Registry] service task failed, staying on poll()");
    } else {
        Serial.println("[Registry] service task started");
    }
}

void SensorRegistry::poll() {
    // With the dedicated task the drivers are serviced there, on their own
    // schedule, even while the main loop is blocked on TLS or the SD card.
    if (!_serviceTaskRunning) serviceModules();

    lock();
    unsigned long now = millis();

    for (auto& rec : _active) {
        if (!rec.online) continue;
        if (!due(now, rec.nextReadAt)) continue;
        readModule(rec);
        uint32_t interval = rec.driver->readInterval();
        if (interval < SENSOR_MIN_READ_INTERVAL_MS)
            interval = SENSOR_MIN_READ_INTERVAL_MS;
        rec.nextReadAt = now + interval;
    }
    unlock();
}

void SensorRegistry::forceRead() {
    lock();
    for (auto& rec : _active) {
        if (rec.online) readModule(rec);
    }
    unlock();
}

size_t SensorRegistry::activeCount() {
    lock();
    size_t n = 0;
    for (auto& rec : _active) {
        if (rec.online) n++;
    }
    unlock();
    return n;
}

unsigned long SensorRegistry::compositionRevision() {
    lock();
    unsigned long r = _revision;
    unlock();
    return r;
}

std::vector<SensorModule*> SensorRegistry::activeModules() {
    lock();
    std::vector<SensorModule*> copy;
    for (auto& rec : _active) {
        if (rec.online) copy.push_back(rec.driver);
    }
    unlock();
    return copy;
}

std::vector<ActiveModule> SensorRegistry::activeRecords() {
    lock();
    std::vector<ActiveModule> copy;
    for (auto& rec : _active) {
        if (rec.online) copy.push_back(rec);
    }
    unlock();
    return copy;
}

String SensorRegistry::modulesToJson() {
    lock();

    String json = "[";
    bool first = true;

    for (auto& rec : _active) {
        indentComma(json, first);
        json += "{";
        json += "\"id\":\"" + activeModuleId(rec) + "\",";
        json += "\"type_id\":" + String(rec.driver->typeId()) + ",";
        json += "\"name\":\"" + String(rec.driver->moduleName()) + "\",";
        json += "\"status\":\"" + String(rec.online ? "online" : "offline") + "\",";
        json += "\"address\":\"0x" + String(rec.address, HEX) + "\",";
        if (rec.muxAddress != 0) {
            json += "\"mux\":{\"address\":\"0x" + String(rec.muxAddress, HEX) +
                    "\",\"channel\":" + String(rec.muxChannel) + "},";
        }
        json += "\"read_interval_ms\":" +
                String(rec.driver->readInterval()) + ",";
        json += "\"last_read_ms\":" + String(rec.lastRead) + ",";

        auto mdefs = rec.driver->metrics();
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

    for (auto& rec : _active) {
        if (!rec.online || rec.cached.empty()) continue;

        // A metric without a valid reading yet (SCD30 warm-up, failed read) is
        // omitted: "nan" is not valid JSON and would break every consumer.
        bool hasValue = false;
        for (auto& m : rec.cached) {
            if (std::isfinite(m.value)) {
                hasValue = true;
                break;
            }
        }
        if (!hasValue) continue;

        indentComma(json, first);
        json += "\"" + activeModuleId(rec) + "\":{";
        bool mfirst = true;
        for (auto& m : rec.cached) {
            if (!std::isfinite(m.value)) continue;
            indentComma(json, mfirst);
            json += "\"" + String(m.key) + "\":" + String(m.value, 2);
        }
        json += "}";
    }

    json += "}}";

    unlock();
    return json;
}