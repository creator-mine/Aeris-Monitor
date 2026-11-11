import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/core/parsers/sensor_frame_parser.dart';

void main() {
  final now = DateTime(2026, 9, 26, 12, 0, 0);

  group('SensorFrameParser', () {
    test('parses module metrics into sensor readings', () {
      final parsed = SensorFrameParser.parse({
        'modules': {
          'bme680_1': {'temperature': 24.5, 'humidity': 60.0, 'pressure': 1013},
          'bh1750_1': {'illuminance': 320},
        },
      }, now, deviceId: 'esp32c3_001');

      expect(parsed.keys.toSet(), {
        'temperature',
        'humidity',
        'pressure',
        'illuminance',
      });
      expect(parsed['temperature']!.getValue('temperature'), 24.5);
      expect(parsed['humidity']!.getValue('humidity'), 60.0);
      expect(parsed['pressure']!.getValue('pressure'), 1013.0);
      expect(parsed['illuminance']!.getValue('illuminance'), 320.0);
      expect(parsed['temperature']!.deviceId, 'esp32c3_001');
      expect(parsed['temperature']!.timestamp, now);
    });

    test('skips non-numeric metrics', () {
      final parsed = SensorFrameParser.parse({
        'modules': {
          'm1': {
            'temperature': 21.0,
            'quality': 'good',
            'flags': [1, 2],
          },
        },
      }, now);

      expect(parsed.keys, ['temperature']);
    });

    test('skips non-map modules and tolerates missing modules', () {
      final parsed = SensorFrameParser.parse({
        'modules': {
          'bad': 'not-a-map',
          'ok': {'x': 1},
        },
      }, now);
      expect(parsed.keys, ['x']);

      expect(SensorFrameParser.parse({}, now), isEmpty);
      expect(SensorFrameParser.parse({'modules': null}, now), isEmpty);
    });

    test('integer values become doubles', () {
      final parsed = SensorFrameParser.parse({
        'modules': {'m': {'reading': 7}},
      }, now);
      expect(parsed['reading']!.getValue('reading'), 7.0);
    });
  });
}