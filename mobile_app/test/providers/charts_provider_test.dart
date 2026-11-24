import 'package:aeris/core/api/mqtt_client.dart';
import 'package:aeris/core/config/connection_mode.dart';
import 'package:aeris/features/charts/providers/charts_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:aeris/models/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMqtt extends MqttService {
  @override
  bool get isConnected => true;

  @override
  Future<List<SensorDataPoint>> requestHistory(
    String deviceId,
    String sensorType, {
    required DateTime since,
    int limit = 500,
  }) async {
    return [SensorDataPoint(timestamp: DateTime(2026, 11, 24, 10), value: 42)];
  }
}

const _illuminanceMetric = MetricInfo(
  key: 'illuminance',
  name: 'Освещённость',
  unit: 'lux',
);

Device _device({required String status, String ip = '192.168.0.117'}) {
  return Device(
    id: 'esp32c6_001',
    name: 'Main Controller C6',
    type: 'esp32c6',
    status: status,
    lastSeen: DateTime(2026, 11, 18, 12),
    ip: ip,
  );
}

void main() {
  test('offline device fails fast with a readable message', () {
    final provider = ChartsProvider();
    final device = _device(status: 'offline');

    provider.setSelectedDevice(
      device.id,
      metrics: const [_illuminanceMetric],
      device: device,
    );

    expect(provider.isLoading, isFalse);
    expect(provider.error, contains('офлайн'));
    expect(provider.error, isNot(contains('DioException')));
  });

  test('offers every known parameter and marks unsupported ones', () {
    final provider = ChartsProvider();
    final device = _device(status: 'online', ip: '');

    provider.setSelectedDevice(
      device.id,
      metrics: const [_illuminanceMetric],
      device: device,
    );

    expect(provider.availableSensorTypes, contains('temperature'));
    expect(provider.availableSensorTypes, contains('humidity'));
    expect(provider.availableSensorTypes, contains('pressure'));
    expect(provider.availableSensorTypes, isNot(contains('gas_resistance')));
    expect(provider.availableSensorTypes, contains('illuminance'));
    expect(provider.isMetricSupported('illuminance'), isTrue);
    expect(provider.isMetricSupported('temperature'), isFalse);
  });

  test('online device without an IP reports the missing channel', () {
    final provider = ChartsProvider();
    final device = _device(status: 'online', ip: '');

    provider.setSelectedDevice(
      device.id,
      metrics: const [_illuminanceMetric],
      device: device,
    );

    expect(provider.isLoading, isFalse);
    expect(provider.error, contains('MQTT'));
  });

  test('loads SD history over MQTT when LAN is disabled', () async {
    LanPolicy.enabled = false;
    try {
      final provider = ChartsProvider(mqtt: _FakeMqtt());
      final device = _device(status: 'online', ip: '192.168.0.117');

      provider.setSelectedDevice(
        device.id,
        metrics: const [_illuminanceMetric],
        device: device,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.error, isNull);
      expect(provider.currentSeries?.points.length, 1);
      expect(provider.currentSeries?.points.first.value, 42);
      expect(provider.currentSeries?.unit, 'lux');
    } finally {
      LanPolicy.enabled = true;
    }
  });
}
