import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iot_modular_app/features/firmware/providers/firmware_provider.dart';
import 'package:iot_modular_app/shared/helpers/chip_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('chip_helper', () {
    test('maps esp32-c3 to ESP32-C3', () {
      expect(expectedChipNameFor('esp32-c3'), 'ESP32-C3');
    });
    test('maps any c6 variant to ESP32-C6', () {
      expect(expectedChipNameFor('esp32-c6'), 'ESP32-C6');
      expect(expectedChipNameFor('esp32-c6-devkit'), 'ESP32-C6');
      expect(expectedChipNameFor('ESP32-C6'), 'ESP32-C6');
    });
    test('maps any s3 variant to ESP32-S3', () {
      expect(expectedChipNameFor('esp32-s3'), 'ESP32-S3');
      expect(expectedChipNameFor('esp32s3'), 'ESP32-S3');
      expect(expectedChipNameFor('ESP32-S3'), 'ESP32-S3');
    });
    test('defaults unknown to ESP32-C3', () {
      expect(expectedChipNameFor('arduino'), 'ESP32-C3');
    });
  });

  group('FirmwareProvider (pure logic)', () {
    test('setPendingVersion accepts valid semver', () {
      final p = FirmwareProvider();
      expect(p.setPendingVersion('1.2.3'), isTrue);
      expect(p.pendingVersion, '1.2.3');
    });

    test('setPendingVersion trims and rejects garbage', () {
      final p = FirmwareProvider();
      expect(p.setPendingVersion('  0.9.1  '), isTrue);
      expect(p.pendingVersion, '0.9.1');
      expect(p.setPendingVersion('abc'), isFalse);
      expect(p.setPendingVersion('1.2'), isFalse);
      expect(p.setPendingVersion('1.2.3.4'), isFalse);
    });

    test('setPendingVersion clears on empty', () {
      final p = FirmwareProvider();
      p.setPendingVersion('1.0.0');
      expect(p.setPendingVersion(''), isTrue);
      expect(p.pendingVersion, isNull);
      expect(p.setPendingVersion('  '), isTrue);
      expect(p.pendingVersion, isNull);
    });

    test('expectedChipName getter follows selected device', () {
      final p = FirmwareProvider();
      expect(p.expectedChipName, 'ESP32-C3');
      p.selectDeviceType('esp32-c6');
      expect(p.expectedChipName, 'ESP32-C6');
      p.selectDeviceType('esp32-s3');
      expect(p.expectedChipName, 'ESP32-S3');
    });
  });
}