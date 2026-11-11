import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/api/ota_api.dart';
import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/devices/providers/devices_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:aeris/models/firmware_manifest.dart';

class _FakeSignalingApi extends SignalingApi {
  _FakeSignalingApi(this.devices, {this.failLoads = false, this.removeFails = false});

  final List<Device> devices;
  final bool failLoads;
  final bool removeFails;

  @override
  Future<List<Device>> getDevices() async {
    if (failLoads) throw Exception('network down');
    return devices;
  }

  @override
  Future<bool> removeDevice(String id) async {
    if (removeFails) throw Exception('remove failed');
    return devices.any((d) => d.id == id);
  }
}

class _FakeOtaApi extends OtaApi {
  _FakeOtaApi(this.manifest);

  final FirmwareManifest? manifest;

  @override
  Future<FirmwareManifest?> fetchManifest({String? deviceType}) async => manifest;
}

Device _device({
  required String id,
  required String status,
  String type = 'esp32-s3',
  String? firmwareVersion,
}) {
  return Device.fromJson({
    'id': id,
    'name': id,
    'type': type,
    'status': status,
    'lastSeen': '2026-09-06T10:00:00.000Z',
    'ip': '192.168.1.5',
    'port': 81,
    if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const published = FirmwareManifest(version: '1.2.2', deviceType: 'esp32-s3');

  group('DevicesProvider', () {
    test('loadDevices populates devices and online/offline filters', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi([
          _device(id: 'a', status: 'online'),
          _device(id: 'b', status: 'offline'),
        ]),
      );

      final loading = provider.loadDevices();
      expect(provider.isLoading, isTrue);
      await loading;
      expect(provider.error, isNull);
      expect(provider.devices.length, 2);
      expect(provider.onlineDevices.length, 1);
      expect(provider.offlineDevices.length, 1);
      expect(provider.getDeviceById('a')?.id, 'a');
      expect(provider.getDeviceById('missing'), isNull);
    });

    test('loadDevices surfaces errors without losing prior state', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi([], failLoads: true),
      );

      await provider.loadDevices();
      expect(provider.error, isNotNull);
      expect(provider.devices, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('refreshDevices loads manifests for known device types', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi([
          _device(id: 'a', status: 'online', firmwareVersion: '1.2.0'),
        ]),
        otaApi: _FakeOtaApi(published),
      );

      await provider.refreshDevices();
      expect(provider.hasManifest, isTrue);
      expect(provider.latestPublishedVersion, '1.2.2');
      expect(provider.manifestFor(provider.devices.first)?.version, '1.2.2');
    });

    test('isOutdated compares device firmware to the published manifest', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi([
          _device(id: 'old', status: 'online', firmwareVersion: '1.2.0'),
          _device(id: 'new', status: 'online', firmwareVersion: '1.2.3'),
          _device(id: 'none', status: 'online'),
        ]),
        otaApi: _FakeOtaApi(published),
      );

      await provider.loadDevices();
      await provider.loadManifest();

      expect(provider.isOutdated(provider.getDeviceById('old')!), isTrue);
      expect(provider.isOutdated(provider.getDeviceById('new')!), isFalse);
      expect(provider.isOutdated(provider.getDeviceById('none')!), isFalse);
    });

    test('deleteDevice removes the device from the list', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi([
          _device(id: 'a', status: 'online'),
          _device(id: 'b', status: 'offline'),
        ]),
      );

      await provider.loadDevices();
      final removed = await provider.deleteDevice('a');
      expect(removed, isTrue);
      expect(provider.devices.length, 1);
      expect(provider.getDeviceById('a'), isNull);
    });

    test('deleteDevice keeps the list and reports an error on failure', () async {
      final provider = DevicesProvider(
        signalingApi: _FakeSignalingApi(
          [_device(id: 'a', status: 'online')],
          removeFails: true,
        ),
      );

      await provider.loadDevices();
      final removed = await provider.deleteDevice('a');
      expect(removed, isFalse);
      expect(provider.devices.length, 1);
      expect(provider.error, isNotNull);
    });
  });
}