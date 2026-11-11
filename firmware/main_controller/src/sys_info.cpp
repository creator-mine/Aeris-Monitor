#include "sys_info.h"
#include <cmath>
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