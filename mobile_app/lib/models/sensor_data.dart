import 'package:equatable/equatable.dart';

class SensorData extends Equatable {
  final String deviceId;
  final String sensorType;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const SensorData({
    required this.deviceId,
    required this.sensorType,
    required this.timestamp,
    required this.data,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> dataMap;
    if (json['data'] is Map<String, dynamic>) {
      dataMap = json['data'] as Map<String, dynamic>;
    } else if (json.containsKey('value')) {
      dataMap = {
        json['sensor'] as String? ?? 'unknown': json['value'],
      };
      if (json.containsKey('unit')) {
        dataMap['unit'] = json['unit'];
      }
    } else {
      dataMap = {};
    }

    return SensorData(
      deviceId: json['device_id'] as String? ?? '',
      sensorType: json['sensor'] as String? ?? '',
      timestamp: _parseTimestamp(json['timestamp']),
      data: dataMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'sensor': sensorType,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'data': data,
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is num) {
      // Accept seconds or milliseconds since epoch.
      final raw = value.toInt();
      final ms = raw < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return _parseTimestamp(asInt);
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  double? getValue(String key) {
    final value = data[key];
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  @override
  List<Object?> get props => [deviceId, sensorType, timestamp, data];
}

class SensorDataPoint extends Equatable {
  final DateTime timestamp;
  final double value;

  const SensorDataPoint({
    required this.timestamp,
    required this.value,
  });

  @override
  List<Object?> get props => [timestamp, value];
}

class SensorDataSeries extends Equatable {
  final String sensorType;
  final String unit;
  final List<SensorDataPoint> points;

  const SensorDataSeries({
    required this.sensorType,
    required this.unit,
    required this.points,
  });

  double get minValue => points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
  double get maxValue => points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
  double get avgValue => points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a + b) / points.length;

  @override
  List<Object?> get props => [sensorType, unit, points];
}
