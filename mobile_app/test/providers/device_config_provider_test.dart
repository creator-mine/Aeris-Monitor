import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/api/ota_api.dart';
import 'package:aeris/core/serial/serial_service.dart';
import 'package:aeris/features/device_config/providers/device_config_provider.dart';
import 'package:aeris/models/firmware_manifest.dart';

class _FakeSerial extends SerialService {
  final StreamController<Map<String, dynamic>> _resp =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _err =
      StreamController<String>.broadcast();

  @override
  Stream<Map<String, dynamic>> get responses => _resp.stream;

  @override
  Stream<String> get errors => _err.stream;

  @override
  bool get isConnected => false;

  void push(Map<String, dynamic> data) => _resp.add(data);

  void pushError(String message) => _err.add(message);

  @override
  void dispose() {
    _resp.close();
    _err.close();
    super.dispose();
  }
}

class _FakeOtaApi extends OtaApi {
  _FakeOtaApi(this.manifest);

  final FirmwareManifest? manifest;
  String? lastDeviceType;

  @override
  Future<FirmwareManifest?> fetchManifest({String? deviceType}) async {
    lastDeviceType = deviceType;
    return manifest;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceConfigProvider', () {
    test('info response populates device info and firmware version', () async {
      final serial = _FakeSerial();
      final provider = DeviceConfigProvider(serial: serial);

      serial.push({
        'type': 'info',
        'firmware': '1.2.2',
        'device_type': 'esp32-s3',
        'mac': 'AA:BB:CC',
      });
      await _flush();

      expect(provider.info?['firmware'], '1.2.2');
      expect(provider.firmwareVersion, '1.2.2');
    });

    test('status and logs responses update state', () async {
      final serial = _FakeSerial();
      final provider = DeviceConfigProvider(serial: serial);

      serial.push({
        'type': 'status',
        'uptime': 42,
        'wifi': 'connected',
      });
      serial.push({
        'type': 'logs',
        'data': [
          {'ts': 1, 'tag': 'Boot', 'msg': 'ready'},
          {'ts': 2, 'tag': 'WiFi', 'msg': 'Connected to home'},
        ],
      });
      await _flush();

      expect(provider.status?['uptime'], 42);
      expect(provider.logs.length, 2);
      expect(provider.logs.first.msg, 'ready');
    });

    test('error and ack responses clear/set error state', () async {
      final serial = _FakeSerial();
      final provider = DeviceConfigProvider(serial: serial);

      serial.push({'type': 'error', 'error': 'bad command'});
      await _flush();
      expect(provider.error, 'bad command');

      serial.push({'type': 'ack'});
      await _flush();
      expect(provider.error, isNull);
    });

    test('checkManifest with injected OTA api drives freshness', () async {
      final serial = _FakeSerial();
      final provider = DeviceConfigProvider(
        serial: serial,
        otaApi: _FakeOtaApi(const FirmwareManifest(
          version: '1.2.2',
          deviceType: 'esp32-s3',
        )),
      );

      serial.push({
        'type': 'info',
        'firmware': '1.2.0',
        'device_type': 'esp32-s3',
      });
      await _flush();
      expect(provider.firmwareVersion, '1.2.0');

      await provider.checkManifest();
      expect(provider.manifest?.version, '1.2.2');
      expect(provider.latestPublishedVersion, '1.2.2');
      expect(provider.freshness.name, 'outdated');
      expect(provider.isOutdated, isTrue);

      serial.push({'type': 'info', 'firmware': '1.2.3', 'device_type': 'esp32-s3'});
      await _flush();
      expect(provider.isOutdated, isFalse);
    });

    test('info response rechecks the manifest for the reported device type',
        () async {
      final serial = _FakeSerial();
      final ota = _FakeOtaApi(const FirmwareManifest(
        version: '1.2.3',
        deviceType: 'esp32-c6',
      ));
      final provider = DeviceConfigProvider(serial: serial, otaApi: ota);

      serial.push({
        'type': 'info',
        'firmware': '1.2.3',
        'device_type': 'esp32c6',
      });
      await _flush();

      expect(ota.lastDeviceType, 'esp32c6');
      expect(provider.manifest?.version, '1.2.3');
      expect(provider.isOutdated, isFalse);
    });

    test('checkManifest without OTA api is a harmless no-op', () async {
      final serial = _FakeSerial();
      final provider = DeviceConfigProvider(serial: serial);

      await provider.checkManifest();
      expect(provider.isCheckingManifest, isFalse);
      expect(provider.manifest, isNull);
    });
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);