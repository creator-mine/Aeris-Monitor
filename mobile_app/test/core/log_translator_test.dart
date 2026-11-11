import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/config/log_mode.dart';
import 'package:aeris/core/utils/log_translator.dart';

void main() {
  group('LogTranslator.display', () {
    test('standard mode keeps the raw English message', () {
      expect(
        LogTranslator.display(
            LogMode.standard, 'ru', 'WiFi', 'Connected to MTS_136'),
        'Connected to MTS_136',
      );
    });

    test('lightweight + English keeps the raw message', () {
      expect(
        LogTranslator.display(
            LogMode.lightweight, 'en', 'WiFi', 'Connected to MTS_136'),
        'Connected to MTS_136',
      );
    });

    test('lightweight + Russian translates the known phrases', () {
      expect(
        LogTranslator.display(
            LogMode.lightweight, 'ru', 'WiFi', 'Connected to MTS_136'),
        'Подключено к MTS_136',
      );
      expect(
        LogTranslator.display(
            LogMode.lightweight, 'ru', 'NTP', 'Time synced 2026-09-27 18:26:53 UTC'),
        'Время синхронизировано',
      );
      expect(
        LogTranslator.display(
            LogMode.lightweight, 'ru', 'MQTT', 'Connected to 2.26.98.234:1883'),
        'Подключено',
      );
      expect(
        LogTranslator.display(LogMode.lightweight, 'ru', 'SD', 'Mount failed'),
        'Карта не обнаружена',
      );
    });

    test('unknown messages pass through unchanged', () {
      expect(
        LogTranslator.display(
            LogMode.lightweight, 'ru', 'Custom', 'Something new happened'),
        'Something new happened',
      );
    });

    test('rules substitute arguments in order', () {
      expect(
        LogTranslator.display(LogMode.lightweight, 'ru', 'Boot',
            'Firmware 1.2.2 starting (chip 240 MHz, 16 MB flash)'),
        'Прошивка 1.2.2 запускается (чип 240 МГц, 16 МБ флеш)',
      );
      expect(
        LogTranslator.display(LogMode.lightweight, 'ru', 'OTA',
            'Downloading 523000 bytes...'),
        'Загрузка 523000 байт...',
      );
      expect(
        LogTranslator.display(LogMode.lightweight, 'ru', 'UART',
            'Module 3 registered: 1 sensor(s), 2 metric(s)'),
        'Модуль 3 зарегистрирован: 1 датчика, 2 метрики',
      );
    });
  });
}