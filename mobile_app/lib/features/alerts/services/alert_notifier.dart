import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import '../../../models/sensor_data.dart';

/// Returns true on desktop platforms where local notifications are supported.
bool localNotificationsAvailable() =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Throttle identical notifications for the same device+sensor so a
/// continuous alarm state does not repeatedly spam the OS notification center.
class AlertNotifier {
  static final Map<String, DateTime> _lastSent = {};
  static const Duration _cooldown = Duration(minutes: 10);

  /// Shows a desktop notification if the flagged sensor is reported.
  static void maybeNotify(SensorData data) {
    if (!localNotificationsAvailable()) return;

    final sensorType = data.sensorType;
    if (sensorType != 'temperature' &&
        sensorType != 'humidity' &&
        sensorType != 'pressure' &&
        sensorType != 'illuminance') {
      return;
    }

    final value = data.getValue(sensorType);
    if (value == null) return;

    final key = '${data.sensorType}';
    final last = _lastSent[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _cooldown) return;

    _lastSent[key] = now;

    final name = _name(sensorType);
    final body =
        'Показания: ${value.toStringAsFixed(1)} ${_unit(sensorType)}';

    LocalNotification(
      title: 'IoT monitor · $name',
      body: body,
    ).show();
  }

  static String _name(String sensorType) => switch (sensorType) {
        'temperature' => 'Температура',
        'humidity' => 'Влажность',
        'pressure' => 'Давление',
        'illuminance' => 'Освещённость',
        _ => sensorType,
      };

  static String _unit(String sensorType) => switch (sensorType) {
        'temperature' => '°C',
        'humidity' => '%',
        'pressure' => 'hPa',
        'illuminance' => 'lx',
        _ => '',
      };
}