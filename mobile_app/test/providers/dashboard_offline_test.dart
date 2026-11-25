import 'package:aeris/core/api/local_device_service.dart';
import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/core/config/connection_mode.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSignaling extends SignalingApi {
  _FailingSignaling() : super(baseUrl: 'http://127.0.0.1:1/api/v1');

  int calls = 0;

  @override
  Future<List<Device>> getDevices() async {
    calls++;
    throw Exception('no internet');
  }
}

class _FakeLocalDevices extends LocalDeviceService {
  _FakeLocalDevices(this.found);

  final List<Device> found;

  @override
  Future<List<Device>> discover({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async =>
      found;

  @override
  Future<void> remember(Device device, {SharedPreferences? prefs}) async {}
}

Device _device(String id, {String ip = '192.168.43.7'}) {
  return Device(
    id: id,
    name: 'S3',
    type: 'esp32s3',
    status: 'online',
    lastSeen: DateTime(2026, 11, 25, 12),
    ip: ip,
    firmwareVersion: '1.4.1',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LAN mode loads the local board without touching the cloud', () async {
    final api = _FailingSignaling();
    final provider = DashboardProvider(
      signalingApi: api,
      mode: ConnectionMode.lanDirect,
      localDevices: _FakeLocalDevices([_device('esp32s3_001')]),
    );

    await provider.loadDevices();

    expect(api.calls, 0);
    expect(provider.devices.single.id, 'esp32s3_001');
    expect(provider.selectedDevice?.id, 'esp32s3_001');
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('auto mode keeps working when the registry is unreachable', () async {
    final api = _FailingSignaling();
    final provider = DashboardProvider(
      signalingApi: api,
      mode: ConnectionMode.auto,
      localDevices: _FakeLocalDevices([_device('esp32s3_001')]),
    );

    await provider.loadDevices();

    expect(api.calls, 1);
    expect(provider.devices, hasLength(1));
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('offline error is a readable hint instead of a DioException', () async {
    final provider = DashboardProvider(
      signalingApi: _FailingSignaling(),
      mode: ConnectionMode.auto,
      localDevices: _FakeLocalDevices(const []),
    );

    await provider.loadDevices();

    expect(provider.devices, isEmpty);
    expect(provider.error, LocalDeviceService.offlineMessage);
    expect(provider.error, isNot(contains('DioException')));
    provider.dispose();
  });
}
