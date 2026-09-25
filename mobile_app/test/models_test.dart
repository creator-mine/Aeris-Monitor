// ignore_for_file: prefer_const_literals_to_create_immutables
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_modular_app/models/alert.dart';
import 'package:iot_modular_app/models/device.dart';
import 'package:iot_modular_app/models/log_entry.dart';
import 'package:iot_modular_app/models/sensor_data.dart';

void main() {
  group('SensorData', () {
    test('parses embedded data map', () {
      final sd = SensorData.fromJson({
        'device_id': 'dev1',
        'sensor': 'bme680',
        'timestamp': 1700000000000,
        'data': {'temperature': 24.5},
      });
      expect(sd.deviceId, 'dev1');
      expect(sd.sensorType, 'bme680');
      expect(sd.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(sd.getValue('temperature'), 24.5);
    });

    test('parses flat value/unit payload', () {
      final sd = SensorData.fromJson({
        'device_id': 'dev1',
        'sensor': 'bh1750',
        'value': 320,
        'unit': 'lx',
      });
      expect(sd.getValue('bh1750'), 320);
      expect(sd.data['unit'], 'lx');
      expect(sd.getValue('unit'), isNull);
    });

    test('missing data becomes empty map', () {
      final sd = SensorData.fromJson({'device_id': 'd', 'sensor': 's'});
      expect(sd.data, isEmpty);
    });

    test('getValue returns null for non-numeric', () {
      final sd = SensorData.fromJson({
        'device_id': 'd',
        'sensor': 's',
        'data': {'x': 'not-a-number'},
      });
      expect(sd.getValue('x'), isNull);
    });
  });

  group('SensorDataSeries', () {
    test('min/max/avg', () {
      final series = SensorDataSeries(
        sensorType: 'temperature',
        unit: '°C',
        points: [
          SensorDataPoint(timestamp: DateTime(2026, 1, 1), value: 10),
          SensorDataPoint(timestamp: DateTime(2026, 1, 1, 1), value: 30),
          SensorDataPoint(timestamp: DateTime(2026, 1, 1, 2), value: 20),
        ],
      );
      expect(series.minValue, 10);
      expect(series.maxValue, 30);
      expect(series.avgValue, 20);
    });

    test('empty series defaults to zero', () {
      const series = SensorDataSeries(sensorType: 't', unit: '', points: []);
      expect(series.minValue, 0);
      expect(series.maxValue, 0);
      expect(series.avgValue, 0);
    });
  });

  group('BME680Data / BH1750Data', () {
    test('BME680 parses values as doubles', () {
      final b = BME680Data.fromMap({
        'temperature': 25,
        'humidity': 60,
        'pressure': 1013,
        'gas_resistance': 100000,
      });
      expect(b.temperature, 25.0);
      expect(b.humidity, 60.0);
      expect(b.gasResistance, 100000.0);
    });

    test('BH1750 parses illuminance', () {
      final l = BH1750Data.fromMap({'illuminance': 512});
      expect(l.illuminance, 512.0);
    });
  });

  group('Device', () {
    test('parses list-of-strings sensors (signaling server format)', () {
      final d = Device.fromJson({
        'id': 'esp32c3_001',
        'name': 'Main',
        'type': 'esp32',
        'status': 'online',
        'lastSeen': '2026-09-06T10:00:00.000Z',
        'ip': '192.168.1.5',
        'port': 81,
        'sensors': ['bme680', 'bh1750'],
      });
      expect(d.id, 'esp32c3_001');
      expect(d.isOnline, isTrue);
      expect(d.sensors.map((s) => s.id), ['bme680', 'bh1750']);
      expect(d.httpBaseUrl, 'http://192.168.1.5:81');
    });

    test('parses legacy object sensors and modules', () {
      final d = Device.fromJson({
        'id': 'old',
        'name': 'Old',
        'type': 'esp32',
        'status': 'offline',
        'lastSeen': 1700000000000,
        'sensors': [
          {'id': 's1', 'type': 'bme680', 'name': 'BME', 'unit': '°C', 'isActive': true},
        ],
        'modules': [
          {
            'id': 'm1',
            'type': 'bme680_module',
            'name': 'BME',
            'status': 'online',
            'config': {'i2c_addr': '0x76'},
            'metrics': [
              {'key': 'temperature', 'name': 'Temp', 'unit': '°C'},
            ],
          },
        ],
      });
      expect(d.status, 'offline');
      expect(d.isOnline, isFalse);
      expect(d.sensors.length, 1);
      expect(d.modules.length, 1);
      expect(d.metricInfo('temperature')?.unit, '°C');
      expect(d.allMetrics.length, 1);
    });

    test('parses firmware type_id modules', () {
      final d = Device.fromJson({
        'id': 'fw',
        'name': 'F',
        'type': 'esp32',
        'status': 'online',
        'lastSeen': '2026-01-01T00:00:00.000Z',
        'modules': [
          {
            'id': 'bme680_1',
            'type_id': 3,
            'name': 'BME680',
            'status': 'online',
            'address': '0x76',
          },
        ],
      });
      expect(d.modules.first.type, 'module_3');
    });

    test('copyWith preserves values and prop equality', () {
      final a = Device.fromJson({
        'id': 'a',
        'name': 'A',
        'type': 'esp32',
        'status': 'online',
        'lastSeen': '2026-01-01T00:00:00Z',
      });
      final b = a.copyWith(ip: '10.0.0.1');
      expect(a, isNot(equals(b)));
      expect(b.ip, '10.0.0.1');
      expect(b.id, 'a');
    });
  });

  group('Alert', () {
    test('roundtrip fromJson/toJson', () {
      final alert = Alert.fromJson({
        'id': 'a1',
        'device_id': 'dev1',
        'sensor_type': 'bme680',
        'type': 'above',
        'threshold': 30,
        'is_active': true,
        'created_at': '2026-09-06T10:00:00.000Z',
        'triggered_at': null,
      });
      expect(alert.type, AlertType.above);
      expect(alert.isActive, isTrue);
      expect(alert.triggeredAt, isNull);
      final round = Alert.fromJson(alert.toJson());
      expect(round.threshold, 30);
      expect(round.id, 'a1');
      expect(round.createdAt, alert.createdAt);
    });

    test('unknown type falls back to above', () {
      final alert = Alert.fromJson({
        'id': 'a2',
        'device_id': 'd',
        'sensor_type': 's',
        'type': 'mystery',
        'threshold': 1,
        'is_active': false,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(alert.type, AlertType.above);
      expect(alert.isActive, isFalse);
    });
  });

  group('LogEntry', () {
    test('parses ts/tag/msg with defaults', () {
      final entry = LogEntry.fromJson(
        {'ts': 1234, 'tag': 'WiFi', 'msg': 'Connected to home'},
      );
      expect(entry.ts, 1234);
      expect(entry.tag, 'WiFi');
      expect(entry.msg, 'Connected to home');
    });

    test('missing fields fall back to defaults', () {
      final entry = LogEntry.fromJson(<String, dynamic>{});
      expect(entry.ts, 0);
      expect(entry.tag, '');
      expect(entry.msg, '');
    });

    test('equality is value-based', () {
      final a = LogEntry(ts: 1, tag: 'Boot', msg: 'ready');
      final b = LogEntry(ts: 1, tag: 'Boot', msg: 'ready');
      final c = LogEntry(ts: 2, tag: 'Boot', msg: 'ready');
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}