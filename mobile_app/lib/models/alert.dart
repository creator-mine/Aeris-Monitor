import 'package:equatable/equatable.dart';

class Alert extends Equatable {
  final String id;
  final String deviceId;
  final String sensorType;
  final AlertType type;
  final double threshold;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt;

  const Alert({
    required this.id,
    required this.deviceId,
    required this.sensorType,
    required this.type,
    required this.threshold,
    this.isActive = true,
    required this.createdAt,
    this.triggeredAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      sensorType: json['sensor_type'] as String,
      type: AlertType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AlertType.above,
      ),
      threshold: (json['threshold'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      triggeredAt: json['triggered_at'] != null
          ? DateTime.parse(json['triggered_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'sensor_type': sensorType,
      'type': type.name,
      'threshold': threshold,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'triggered_at': triggeredAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, deviceId, sensorType, type, threshold, isActive, createdAt, triggeredAt];
}

enum AlertType {
  above,
  below,
  equals,
}
