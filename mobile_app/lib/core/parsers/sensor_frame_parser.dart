import '../../models/sensor_data.dart';

/// Parses the device "sensor_update" frame payload into plain readings.
///
/// Frame shape (from the ESP32 WS/MQTT data channel):
/// ```json
/// {
///   "device_id": "esp32c3_001",
///   "modules": {
///     "bme680_1": {"temperature": 24.5, "humidity": 60.0, "pressure": 1013.2},
///     "bh1750_1": {"illuminance": 320}
///   }
/// }
/// ```
/// Non-map modules and non-numeric metrics are skipped; empty input yields
/// an empty map.
class SensorFrameParser {
  const SensorFrameParser._();

  static Map<String, SensorData> parse(
    Map<String, dynamic> data,
    DateTime now, {
    String deviceId = '',
  }) {
    final result = <String, SensorData>{};
    final modules = data['modules'];
    if (modules is! Map) return result;

    modules.forEach((moduleId, metrics) {
      if (metrics is! Map) return;
      metrics.forEach((key, value) {
        if (value is num) {
          result[key.toString()] = SensorData(
            deviceId: deviceId,
            sensorType: key.toString(),
            timestamp: now,
            data: {key.toString(): value.toDouble()},
          );
        }
      });
    });

    return result;
  }
}