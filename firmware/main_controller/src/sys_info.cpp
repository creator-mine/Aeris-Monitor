#include "sys_info.h"
#include <cmath>

#if defined(CONFIG_IDF_TARGET_ESP32)
// The original ESP32 has no temperature-sensor driver in the Arduino core 3.x
// build (no libesp_driver_tsens.a). Return "unavailable" so callers omit the
// optional chip_temp field instead of failing to link.
float chipTemperatureCelsius() { return NAN; }
#else
#include <driver/temperature_sensor.h>

namespace {

temperature_sensor_handle_t gTempSensor = nullptr;

// Lazy-init the internal TSENS driver once; further calls reuse the handle.
bool tempSensorReady() {
    if (gTempSensor != nullptr) return true;

    temperature_sensor_config_t cfg =
        TEMPERATURE_SENSOR_CONFIG_DEFAULT(0, 80);
    if (temperature_sensor_install(&cfg, &gTempSensor) != ESP_OK) {
        return false;
    }
    return temperature_sensor_enable(gTempSensor) == ESP_OK;
}

} // namespace

float chipTemperatureCelsius() {
    if (!tempSensorReady()) return NAN;
    float celsius = NAN;
    if (temperature_sensor_get_celsius(gTempSensor, &celsius) != ESP_OK) {
        return NAN;
    }
    return celsius;
}
#endif  // CONFIG_IDF_TARGET_ESP32