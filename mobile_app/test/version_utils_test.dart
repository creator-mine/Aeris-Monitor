import 'package:flutter_test/flutter_test.dart';
import 'package:iot_modular_app/core/utils/version.dart';
import 'package:iot_modular_app/models/firmware_manifest.dart';

void main() {
  group('parseVersion', () {
    test('parses plain dotted versions', () {
      expect(parseVersion('1.2.3'), [1, 2, 3]);
      expect(parseVersion('1.2'), [1, 2]);
      expect(parseVersion('0.0.1'), [0, 0, 1]);
    });

    test('strips leading v and ignores suffixes', () {
      expect(parseVersion('v1.2.3'), [1, 2, 3]);
      expect(parseVersion('1.2.3-beta1'), [1, 2, 3]);
    });

    test('rejects empty and garbage', () {
      expect(parseVersion(''), isEmpty);
      expect(parseVersion(null), isEmpty);
      expect(parseVersion('abc'), isEmpty);
    });
  });

  group('compareVersions', () {
    test('orders versions numerically', () {
      expect(compareVersions('1.2.3', '1.2.2'), 1);
      expect(compareVersions('1.2.2', '1.2.3'), -1);
      expect(compareVersions('1.2.3', '1.2.3'), 0);
      expect(compareVersions('v1.2.3', '1.2.3'), 0);
    });

    test('treats missing parts as zero', () {
      expect(compareVersions('1.2', '1.2.3'), -1);
      expect(compareVersions('1.2.10', '1.2.9'), 1);
      expect(compareVersions('2.0.0', '1.9.9'), 1);
    });

    test('treats unparseable versions as older', () {
      expect(compareVersions('', '1.0.0'), -1);
      expect(compareVersions('garbage', '1.0.0'), -1);
      expect(compareVersions('1.0.0', null), 1);
      expect(compareVersions('', ''), 0);
    });

    test('isVersionNewer', () {
      expect(isVersionNewer('1.2.3', '1.2.2'), isTrue);
      expect(isVersionNewer('1.2.2', '1.2.3'), isFalse);
      expect(isVersionNewer('1.2.3', '1.2.3'), isFalse);
    });
  });

  group('firmwareFreshness', () {
    test('detects outdated / latest / newer', () {
      expect(firmwareFreshness('1.2.1', '1.2.2'), FirmwareFreshness.outdated);
      expect(firmwareFreshness('1.2.2', '1.2.2'), FirmwareFreshness.latest);
      expect(firmwareFreshness('1.2.3', '1.2.2'), FirmwareFreshness.newer);
    });

    test('returns unknown when either side is missing', () {
      expect(firmwareFreshness(null, '1.2.2'), FirmwareFreshness.unknown);
      expect(firmwareFreshness('1.2.2', null), FirmwareFreshness.unknown);
      expect(firmwareFreshness('', '1.2.2'), FirmwareFreshness.unknown);
    });
  });

  group('FirmwareManifest', () {
    test('parses a full manifest', () {
      final manifest = FirmwareManifest.fromJson({
        'version': '1.2.2',
        'device_type': 'esp32-c3',
        'build_date': '2026-09-11T08:15:00.000Z',
        'sha256': 'a' * 64,
        'file': 'main.bin',
      });
      expect(manifest.version, '1.2.2');
      expect(manifest.deviceType, 'esp32-c3');
      expect(manifest.buildDate, DateTime.parse('2026-09-11T08:15:00.000Z'));
      expect(manifest.sha256, 'a' * 64);
      expect(manifest.file, 'main.bin');
    });

    test('tolerates missing optional fields', () {
      final manifest = FirmwareManifest.fromJson({'version': '1.0.0'});
      expect(manifest.version, '1.0.0');
      expect(manifest.deviceType, 'esp32-c3');
      expect(manifest.buildDate, isNull);
      expect(manifest.sha256, isNull);
    });

    test('tryParse accepts raw maps and rejects non-maps', () {
      expect(FirmwareManifest.tryParse({'version': '1.0.0'}), isNotNull);
      expect(FirmwareManifest.tryParse('1.0.0'), isNull);
      expect(FirmwareManifest.tryParse(null), isNull);
    });
  });
}