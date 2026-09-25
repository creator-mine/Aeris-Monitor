import 'package:equatable/equatable.dart';
import '../core/config/app_config.dart';

class MetricInfo extends Equatable {
  final String key;
  final String name;
  final String unit;

  const MetricInfo({
    required this.key,
    required this.name,
    required this.unit,
  });

  factory MetricInfo.fromJson(Map<String, dynamic> json) {
    return MetricInfo(
      key: json['key'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'unit': unit,
    };
  }

  @override
  List<Object?> get props => [key, name, unit];
}

class Device extends Equatable {
  final String id;
  final String name;
  final String type;
  final String status;
  final DateTime lastSeen;
  final String ip;
  final int port;
  final List<Sensor> sensors;
  final List<Module> modules;
  final String? firmwareVersion;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.lastSeen,
    this.ip = '',
    this.port = 80,
    this.sensors = const [],
    this.modules = const [],
    this.firmwareVersion,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      lastSeen: _parseDate(json['lastSeen']),
      ip: (json['ip'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 80,
      sensors: _parseSensors(json['sensors']),
      modules: (json['modules'] as List<dynamic>?)
              ?.map((m) => Module.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      firmwareVersion: (json['firmwareVersion'] as String?)?.trim(),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.now();
  }

  static List<Sensor> _parseSensors(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      // signaling server: ["temperature", "humidity", ...]
      if (value.isNotEmpty && value.first is String) {
        return value
            .map((s) => Sensor(
                  id: s as String,
                  type: s,
                  name: s,
                  unit: '',
                  isActive: true,
                ))
            .toList();
      }
      // old REST server: [{id, type, name, unit, isActive}]
      return value
          .map((s) => Sensor.fromJson(s as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'status': status,
      'lastSeen': lastSeen.toIso8601String(),
      'ip': ip,
      'port': port,
      'sensors': sensors.map((s) => s.toJson()).toList(),
      'modules': modules.map((m) => m.toJson()).toList(),
      if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
    };
  }

  Device copyWith({
    String? id,
    String? name,
    String? type,
    String? status,
    DateTime? lastSeen,
    String? ip,
    int? port,
    List<Sensor>? sensors,
    List<Module>? modules,
    String? firmwareVersion,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      sensors: sensors ?? this.sensors,
      modules: modules ?? this.modules,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    );
  }

  bool get isOnline => status == 'online';

  String? get httpBaseUrl {
    if (ip.isEmpty) return null;
    return 'http://$ip:$port';
  }

  String? get wsUrl {
    if (ip.isEmpty) return null;
    return 'ws://$ip:${AppConfig.deviceWsPort}/ws';
  }

  List<MetricInfo> get allMetrics {
    final map = <String, MetricInfo>{};
    for (final module in modules) {
      for (final metric in module.metrics) {
        map[metric.key] = metric;
      }
    }
    return map.values.toList();
  }

  MetricInfo? metricInfo(String key) {
    for (final module in modules) {
      for (final metric in module.metrics) {
        if (metric.key == key) return metric;
      }
    }
    return null;
  }

  @override
  List<Object?> get props =>
      [id, name, type, status, lastSeen, ip, port, sensors, modules, firmwareVersion];
}

class Sensor extends Equatable {
  final String id;
  final String type;
  final String name;
  final String unit;
  final bool isActive;

  const Sensor({
    required this.id,
    required this.type,
    required this.name,
    required this.unit,
    this.isActive = true,
  });

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'unit': unit,
      'isActive': isActive,
    };
  }

  @override
  List<Object?> get props => [id, type, name, unit, isActive];
}

class Module extends Equatable {
  final String id;
  final String type;
  final String name;
  final String status;
  final Map<String, dynamic> config;
  final List<MetricInfo> metrics;

  const Module({
    required this.id,
    required this.type,
    required this.name,
    required this.status,
    this.config = const {},
    this.metrics = const [],
  });

  factory Module.fromJson(Map<String, dynamic> json) {
    // Firmware modules JSON: {id, type_id (int), name, status, address, metrics}
    // Legacy REST server:    {id, type (String), name, status, config, metrics}
    final typeId = json['type_id'];
    final legacyType = json['type'];
    return Module(
      id: (json['id'] as String?) ?? '',
      type: (legacyType is String)
          ? legacyType
          : (typeId is num ? 'module_$typeId' : ''),
      name: (json['name'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unknown',
      config: json['config'] as Map<String, dynamic>? ?? {},
      metrics: (json['metrics'] as List<dynamic>?)
              ?.map((m) => MetricInfo.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'status': status,
      'config': config,
      'metrics': metrics.map((m) => m.toJson()).toList(),
    };
  }

  bool get isOnline => status == 'online';

  @override
  List<Object?> get props => [id, type, name, status, config, metrics];
}
