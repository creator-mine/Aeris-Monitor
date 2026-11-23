import 'dart:async';
import 'dart:convert';

import 'package:aeris/core/api/mqtt_client.dart';
import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSignalingApi extends SignalingApi {
  _FakeSignalingApi(this.devices);

  final List<Device> devices;

  @override
  Future<List<Device>> getDevices() async => devices;
}

class _FakeMqtt extends MqttService {
  final _statuses = StreamController<String>.broadcast();
  String? cached;

  @override
  Stream<String> get statusStream => _statuses.stream;

  @override
  bool get isConnected => true;

  @override
  String? latestStatus(
    String deviceId, {
    Duration maxAge = const Duration(minutes: 2),
  }) =>
      cached;

  void emit(String payload) => _statuses.add(payload);
}

void main() {
  test('dashboard shows the SD card from an MQTT status frame', () async {
    final mqtt = _FakeMqtt();
    final device = Device(
      id: 'esp32s3_001',
      name: 'S3',
      type: 'esp32s3',
      status: 'online',
      lastSeen: DateTime.now(),
      ip: '192.168.0.162',
    );
    final provider = DashboardProvider(
      signalingApi: _FakeSignalingApi([device]),
      mqtt: mqtt,
    );

    mqtt.emit(jsonEncode({
      'device_id': 'esp32s3_001',
      'device_type': 'esp32s3',
      'status': 'online',
      'sd': {
        'status': 'ok',
        'mounted': true,
        'card_detected': true,
        'card_type': 'SDHC',
        'type': 'SDHC',
        'total_bytes': 62494670848,
        'used_bytes': 2424832,
        'free_bytes': 62492246016,
        'used_pct': 0,
      },
      'modules': ['BH1750', 'BME680'],
    }));
    await Future<void>.delayed(Duration.zero);

    // ignore: avoid_print
    print('sd=${provider.sdCard}');
    expect(provider.sdCard?.isOk, isTrue);
    provider.dispose();
  });

  test('selecting a device restores the cached MQTT SD card immediately',
      () async {
    final mqtt = _FakeMqtt()
      ..cached = jsonEncode({
        'device_id': 'esp32s3_001',
        'sd': {
          'status': 'ok',
          'mounted': true,
          'card_detected': true,
          'type': 'SDHC',
          'total_bytes': 1000,
          'used_bytes': 100,
          'free_bytes': 900,
          'used_pct': 10,
        },
      });
    final device = Device(
      id: 'esp32s3_001',
      name: 'S3',
      type: 'esp32s3',
      status: 'online',
      lastSeen: DateTime.now(),
      ip: '192.168.0.162',
    );
    final provider = DashboardProvider(
      signalingApi: _FakeSignalingApi([device]),
      mqtt: mqtt,
    );

    await provider.selectDevice(device);

    expect(provider.sdCard?.usedPercent, 10);
    provider.dispose();
  });
}
