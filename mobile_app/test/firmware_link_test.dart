import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/utils/firmware_file.dart';
import 'package:aeris/core/utils/firmware_link.dart';

void main() {
  group('FirmwareLink.parse', () {
    test('accepts a raw GitHub file', () {
      final link = FirmwareLink.parse(
        'https://raw.githubusercontent.com/Spe4naz/Aeris-firmware/main/fw/main_esp32-c6.bin',
      );
      expect(link, isNotNull);
      expect(link!.isGithubRelease, isFalse);
      expect(link.directUri.toString(), contains('main_esp32-c6.bin'));
    });

    test('converts a GitHub blob page to raw', () {
      final link = FirmwareLink.parse(
        'https://github.com/Spe4naz/Aeris-firmware/blob/main/fw/main_esp32-c6.bin',
      );
      expect(link, isNotNull);
      expect(link!.directUri?.host, 'raw.githubusercontent.com');
      expect(
        link.directUri?.path,
        '/Spe4naz/Aeris-firmware/main/fw/main_esp32-c6.bin',
      );
    });

    test('accepts a release asset download URL', () {
      final link = FirmwareLink.parse(
        'https://github.com/Spe4naz/Aeris-firmware/releases/download/v1.2.2/iot-modular-esp32c3-v1.2.2.bin',
      );
      expect(link, isNotNull);
      expect(link!.isGithubRelease, isFalse);
      expect(link.directUri?.host, 'github.com');
    });

    test('accepts the latest release download shortcut', () {
      final link = FirmwareLink.parse(
        'https://github.com/Spe4naz/Aeris-firmware/releases/latest/download/main_esp32-c6.bin',
      );
      expect(link, isNotNull);
      expect(link!.isGithubRelease, isFalse);
      expect(link.directUri?.path, contains('main_esp32-c6.bin'));
    });

    test('accepts a latest release and repository root', () {
      final latest = FirmwareLink.parse(
        'https://github.com/Spe4naz/Aeris-firmware/releases/latest',
      );
      expect(latest, isNotNull);
      expect(latest!.isGithubRelease, isTrue);
      expect(latest.owner, 'Spe4naz');
      expect(latest.repo, 'Aeris-firmware');
      expect(latest.tag, isNull);

      final repo = FirmwareLink.parse('github.com/Spe4naz/Aeris-firmware');
      expect(repo, isNotNull);
      expect(repo!.isGithubRelease, isTrue);
    });

    test('accepts a specific release tag', () {
      final link = FirmwareLink.parse(
        'https://github.com/Spe4naz/Aeris-firmware/releases/tag/v1.3.2',
      );
      expect(link, isNotNull);
      expect(link!.isGithubRelease, isTrue);
      expect(link.tag, 'v1.3.2');
    });

    test('accepts any HTTPS .bin URL', () {
      final link = FirmwareLink.parse(
        'https://spe4naz.online/fw/main_esp32-c6.bin',
      );
      expect(link, isNotNull);
      expect(link!.isGithubRelease, isFalse);
    });

    test('rejects insecure or non-firmware links', () {
      expect(FirmwareLink.parse('http://example.com/fw.bin'), isNull);
      expect(FirmwareLink.parse('https://example.com/readme.txt'), isNull);
      expect(FirmwareLink.parse('https://github.com/o/r'), isNotNull);
      expect(FirmwareLink.parse('ftp://example.com/fw.bin'), isNull);
      expect(FirmwareLink.parse(''), isNull);
    });
  });

  group('firmware file names', () {
    test('detects board type from release assets', () {
      expect(
        firmwareDeviceTypeFromName('iot-modular-esp32c3-v1.2.2.bin'),
        'esp32-c3',
      );
      expect(
        firmwareDeviceTypeFromName('iot-modular-esp32c6-v1.0.0.bin'),
        'esp32-c6',
      );
      expect(
        firmwareDeviceTypeFromName('iot-modular-esp32s3-v1.2.2.bin'),
        'esp32-s3',
      );
      expect(firmwareDeviceTypeFromName('main.bin'), isNull);
      expect(firmwareDeviceTypeFromName('firmware.bin'), isNull);
      expect(firmwareDeviceTypeFromName('mystery.bin'), isNull);
    });

    test('extracts the version from a filename', () {
      expect(
        firmwareVersionFromName('iot-modular-esp32c6-v1.3.2.bin'),
        '1.3.2',
      );
      expect(firmwareVersionFromName('main_esp32-c6.bin'), isNull);
    });

    test('sanitizes unsafe names and keeps .bin', () {
      expect(safeFirmwareFileName('../../evil name.bin'), 'evil_name.bin');
      expect(safeFirmwareFileName('firmware'), 'firmware.bin');
      expect(safeFirmwareFileName(''), 'firmware.bin');
    });
  });
}
