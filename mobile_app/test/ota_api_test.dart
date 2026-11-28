import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/api/ota_api.dart';
import 'package:aeris/core/config/app_config.dart';

void main() {
  group('OtaApi baseUrl normalization', () {
    test('defaults to the built-in host', () {
      expect(OtaApi().baseUrl, AppConfig.apiBaseUrl);
    });
    test('blank/whitespace falls back to the default', () {
      expect(OtaApi(baseUrl: '').baseUrl, AppConfig.apiBaseUrl);
      expect(OtaApi(baseUrl: '   ').baseUrl, AppConfig.apiBaseUrl);
    });
    test('trims trailing slashes for self-hosting', () {
      expect(
        OtaApi(baseUrl: 'https://iot.example.com///').baseUrl,
        'https://iot.example.com',
      );
      expect(
        OtaApi(baseUrl: 'http://192.168.1.10').baseUrl,
        'http://192.168.1.10',
      );
    });
  });
  group('OtaApi.normalizeDeviceType', () {
    test('maps app selector esp32-c3', () {
      expect(OtaApi.normalizeDeviceType('esp32-c3'), 'esp32-c3');
    });
    test('maps registry spelling esp32s3', () {
      expect(OtaApi.normalizeDeviceType('esp32s3'), 'esp32-s3');
    });
    test('maps hyphenated s3 spelling', () {
      expect(OtaApi.normalizeDeviceType('esp32-s3'), 'esp32-s3');
      expect(OtaApi.normalizeDeviceType('ESP32-S3'), 'esp32-s3');
    });
    test('maps c6 and unknown pass-through', () {
      expect(OtaApi.normalizeDeviceType('esp32-c6'), 'esp32-c6');
      expect(OtaApi.normalizeDeviceType('custom'), 'custom');
    });
    test('maps classic ESP32 without swallowing c3/c6/s3', () {
      expect(OtaApi.normalizeDeviceType('esp32'), 'esp32');
      expect(OtaApi.normalizeDeviceType('esp32dev'), 'esp32');
      expect(OtaApi.normalizeDeviceType('ESP32-CLASSIC'), 'esp32');
      expect(OtaApi.normalizeDeviceType('esp32c3'), 'esp32-c3');
      expect(OtaApi.normalizeDeviceType('esp32c6'), 'esp32-c6');
      expect(OtaApi.normalizeDeviceType('esp32s3'), 'esp32-s3');
    });
    test('falls back to esp32-c3 when empty', () {
      expect(OtaApi.normalizeDeviceType(null), 'esp32-c3');
      expect(OtaApi.normalizeDeviceType(''), 'esp32-c3');
    });
  });

  group('OtaApi manifest/binary paths', () {
    test('esp32-c3 keeps the legacy layout', () {
      expect(OtaApi.manifestPathFor('esp32-c3'), '/fw/version.json');
      expect(OtaApi.manifestPathFor(null), '/fw/version.json');
      expect(OtaApi.binaryPathFor('esp32-c3'), '/fw/main.bin');
    });
    test('esp32-s3 has per-device_type files', () {
      expect(OtaApi.manifestPathFor('esp32-s3'), '/fw/version-esp32-s3.json');
      expect(OtaApi.manifestPathFor('esp32s3'), '/fw/version-esp32-s3.json');
      expect(OtaApi.binaryPathFor('esp32-s3'), '/fw/main_esp32-s3.bin');
    });
    test('esp32-c6 controller has its own files', () {
      expect(OtaApi.manifestPathFor('esp32-c6'), '/fw/version-esp32-c6.json');
      expect(OtaApi.manifestPathFor('esp32c6'), '/fw/version-esp32-c6.json');
      expect(OtaApi.binaryPathFor('esp32-c6'), '/fw/main_esp32-c6.bin');
      expect(OtaApi.binaryPathFor('esp32c6'), '/fw/main_esp32-c6.bin');
    });
    test('classic ESP32 has its own files', () {
      expect(OtaApi.manifestPathFor('esp32'), '/fw/version-esp32.json');
      expect(OtaApi.manifestPathFor('esp32dev'), '/fw/version-esp32.json');
      expect(OtaApi.binaryPathFor('esp32'), '/fw/main_esp32.bin');
      expect(OtaApi.binaryPathFor('esp32dev'), '/fw/main_esp32.bin');
    });
    test('unknown types fall back to legacy files', () {
      expect(OtaApi.manifestPathFor('custom'), '/fw/version.json');
      expect(OtaApi.binaryPathFor('custom'), '/fw/main.bin');
    });
  });
}