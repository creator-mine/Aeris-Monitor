#include "bme680_module.h"
#include "sensor_registry.h"
#include <Preferences.h>
#include <Wire.h>
#include <cmath>

namespace {

constexpr const char* kStateNamespace = "bsec";
constexpr const char* kStateKey = "iaq";

// The algorithm keeps refining its baseline for days. Saving every six hours
// bounds what a power cut can cost without wearing the NVS flash; accuracy
// level changes are saved immediately, because they are the expensive part.
constexpr unsigned long kStateSaveIntervalMs = 6UL * 60UL * 60UL * 1000UL;

// Profile shipped with the BSEC2 library: BME680, 3.3 V, one measurement every
// 3 s, four-day calibration. Included straight from the dependency so the
// Bosch blob is never copied into this repository.
const uint8_t kIaqConfig[] = {
#include "config/bme680/bme680_iaq_33v_3s_4d/bsec_iaq.txt"
};

}  // namespace

std::vector<uint8_t> BME680Module::i2cAddresses() const {
    return {0x76, 0x77};
}

// BME680 and BMP280 both answer on 0x76/0x77, so an ACK alone is not enough:
// the chip id decides which driver owns the address. BME680 returns 0x61
// (0x60 is a BME280, which this driver does not handle).
bool BME680Module::detect(uint8_t address) {
    uint8_t chipId = 0;
    if (!readSensorRegister(address, 0xD0, chipId)) return false;
    Serial.printf("[BME680] probe 0x%02X chip id=0x%02X\n", address, chipId);
    return chipId == 0x61;
}

bool BME680Module::init(uint8_t address) {
    _address = address;

    // Allocate the BSEC instance statically. The default begin() would put it
    // on the heap and every recovery would allocate a new one without freeing
    // the old instance.
    _bsec.allocateMemory(_memBlock);
    if (!_bsec.begin(address, Wire)) {
        Serial.printf("[BME680] BSEC init failed at 0x%02X (status %d)\n",
                      address, (int)_bsec.status);
        return false;
    }

    if (!_bsec.setConfig(kIaqConfig)) {
        Serial.printf("[BME680] BSEC config rejected at 0x%02X (status %d)\n",
                      address, (int)_bsec.status);
        return false;
    }

    loadState();

    bsecSensor sensors[] = {
        BSEC_OUTPUT_IAQ,
        // RAW_TEMPERATURE/HUMIDITY still contain the gas-heater self-heating
        // cycle, which shows up as regular 0.5-1 °C spikes in charts. The
        // heat-compensated outputs are the values meant for display/logging.
        BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
        BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
        BSEC_OUTPUT_RAW_PRESSURE,
    };
    if (!_bsec.updateSubscription(sensors, ARRAY_LEN(sensors),
                                  BSEC_SAMPLE_RATE_LP)) {
        Serial.printf("[BME680] BSEC subscription failed (status %d)\n",
                      (int)_bsec.status);
        return false;
    }
    // Default self-heating offset for the 3 s low-power profile, measured by
    // Bosch on their reference board.
    _bsec.setTemperatureOffset(TEMP_OFFSET_LP);

    _ready = true;
    _active = true;
    _lastStateSave = millis();

    Serial.printf("[BME680] BSEC %u.%u.%u.%u ready at 0x%02X\n",
                  _bsec.version.major, _bsec.version.minor,
                  _bsec.version.major_bugfix, _bsec.version.minor_bugfix,
                  address);
    return true;
}

// Called from the registry service task (or poll() when no task is running)
// for every online module. BSEC must be serviced far more often than the 3 s
// output rate: run() decides internally when the next measurement is due and
// returns immediately otherwise.
void BME680Module::service() {
    if (!_ready) return;

    if (!_bsec.run()) {
        // Warnings (for example a late sample window after a long SD write)
        // are not fatal: the next call resynchronises on its own. Only real
        // errors are worth a log line and a skipped capture.
        if (_bsec.status < BSEC_OK) {
            if (_lastErrorLog == 0 || millis() - _lastErrorLog > 60000) {
                _lastErrorLog = millis();
                Serial.printf("[BME680] BSEC run failed (status %d)\n",
                              (int)_bsec.status);
            }
            return;
        }
    }

    if (const bsecOutputs* outputs = _bsec.getOutputs()) {
        captureOutputs(*outputs);
    }

    if (_stateDirty || millis() - _lastStateSave >= kStateSaveIntervalMs) {
        _stateDirty = false;
        saveState();
    }
}

std::vector<Metric> BME680Module::read() {
    if (!_ready) return {};

    return {
        {"temperature", _temperature, "C"},
        {"humidity", _humidity, "%"},
        {"pressure", _pressure, "hPa"},
        {"iaq", _iaq, ""},
        {"iaq_accuracy", _iaqAccuracy, ""},
    };
}

std::vector<MetricDef> BME680Module::metrics() const {
    return {
        {"temperature", "Temperature", "C"},
        {"humidity", "Humidity", "%"},
        {"pressure", "Pressure", "hPa"},
        {"iaq", "Air Quality (IAQ)", ""},
        {"iaq_accuracy", "IAQ Accuracy", ""},
    };
}

void BME680Module::captureOutputs(const bsecOutputs& outputs) {
    for (uint8_t i = 0; i < outputs.nOutputs; i++) {
        const bsecData& out = outputs.output[i];
        switch (out.sensor_id) {
            case BSEC_OUTPUT_IAQ: {
                _iaq = out.signal;
                bool accuracyChanged =
                    !std::isfinite(_iaqAccuracy) ||
                    (uint8_t)_iaqAccuracy != out.accuracy;
                _iaqAccuracy = out.accuracy;
                if (accuracyChanged) {
                    Serial.printf("[BME680] IAQ %.0f accuracy %u/3\n",
                                  _iaq, out.accuracy);
                    // Keep the calibration milestones even if power is lost
                    // right after this measurement.
                    if (out.accuracy > 0) _stateDirty = true;
                }
                break;
            }
            case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
                _temperature = out.signal;
                break;
            case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
                _humidity = out.signal;
                break;
            case BSEC_OUTPUT_RAW_PRESSURE:
                if (!_pressureLogged) {
                    _pressureLogged = true;
                    Serial.printf("[BME680] BSEC pressure %.1f hPa\n", out.signal);
                }
                // BSEC2 converts the sensor's pascal reading to hPa before
                // feeding the algorithm, and RAW_PRESSURE already carries it.
                _pressure = out.signal;
                break;
            default:
                break;
        }
    }
}

void BME680Module::loadState() {
    Preferences prefs;
    if (!prefs.begin(kStateNamespace, true)) return;

    size_t len = prefs.getBytesLength(kStateKey);
    if (len == BSEC_MAX_STATE_BLOB_SIZE) {
        uint8_t state[BSEC_MAX_STATE_BLOB_SIZE] = {};
        prefs.getBytes(kStateKey, state, sizeof(state));
        if (_bsec.setState(state)) {
            Serial.println("[BME680] BSEC state restored");
        } else {
            // State is tied to the library version and the configuration:
            // after an upgrade it is simply discarded and calibration restarts.
            Serial.printf("[BME680] BSEC state rejected (status %d)\n",
                          (int)_bsec.status);
        }
    }
    prefs.end();
}

void BME680Module::saveState() {
    uint8_t state[BSEC_MAX_STATE_BLOB_SIZE] = {};
    if (!_bsec.getState(state)) return;

    Preferences prefs;
    if (!prefs.begin(kStateNamespace, false)) return;
    prefs.putBytes(kStateKey, state, sizeof(state));
    prefs.end();

    _lastStateSave = millis();
    Serial.println("[BME680] BSEC state saved");
}

REGISTER_SENSOR(BME680Module)
