import 'package:aeris/models/sd_card_info.dart';
import 'package:aeris/shared/utils/byte_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a mounted SD card from /sd/info', () {
    final info = SdCardInfo.fromJson(const {
      'status': 'ok',
      'mounted': true,
      'card_detected': true,
      'type': 'SDHC',
      'total_bytes': 64021856256,
      'used_bytes': 5120000000,
      'free_bytes': 58901856256,
      'used_pct': 8,
    });

    expect(info.isOk, isTrue);
    expect(info.cardType, 'SDHC');
    expect(info.usedPercent, 8);
    expect(info.usedFraction, closeTo(0.08, 0.0001));
    expect(info.freeBytes, 58901856256);
  });

  test('computes the percentage when the firmware omits used_pct', () {
    final info = SdCardInfo.fromJson(const {
      'mounted': true,
      'total_bytes': 1000,
      'used_bytes': 250,
    });

    expect(info.status, 'ok');
    expect(info.usedPercent, 25);
    expect(info.freeBytes, 750);
  });

  test('reports missing and failed cards distinctly', () {
    final noCard = SdCardInfo.fromJson(const {
      'status': 'no_card',
      'mounted': false,
      'card_detected': false,
    });
    final failed = SdCardInfo.fromJson(const {
      'status': 'mount_failed',
      'mounted': false,
      'card_detected': true,
      'card_type': 'SDHC',
      'card_bytes': 64000000000,
    });

    expect(noCard.isOk, isFalse);
    expect(noCard.status, 'no_card');
    expect(failed.status, 'mount_failed');
    expect(failed.cardDetected, isTrue);
  });

  test('reads the nested status frame from firmware 1.3.6', () {
    final info = SdCardInfo.tryFromStatus({
      'firmware': '1.3.6',
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

    expect(info, isNotNull);
    expect(info!.usedPercent, 10);
  });

  test('returns null for older status frames without SD data', () {
    expect(SdCardInfo.tryFromStatus({'firmware': '1.3.5'}), isNull);
  });

  test('formats byte sizes for both languages', () {
    expect(formatBytes(0, language: 'ru'), '0 Б');
    expect(formatBytes(1536, language: 'ru'), '1,5 КБ');
    expect(formatBytes(64021856256, language: 'ru'), '59,6 ГБ');
    expect(formatBytes(1536, language: 'en'), '1.5 KB');
    expect(formatBytes(64021856256, language: 'en'), '59.6 GB');
  });
}
