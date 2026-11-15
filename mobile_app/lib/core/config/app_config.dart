import 'package:flutter/material.dart';

class AppConfig {
  static const String appName = 'Aeris Monitor';
  static const String appVersion = '1.2.1';
  
  // API Configuration
  static const String apiBaseUrl = 'https://spe4naz.online';
  static const String apiVersion = '/api/v1';

  // Signaling Server (device discovery — registry only)
  static const String signalingUrl = 'https://spe4naz.online';
  static const String signalingApiVersion = '/api/v1';

  // Direct device connection
  static const int deviceHttpPort = 80;
  static const int deviceWsPort = 80;

  // MQTT Configuration (primary remote transport via VPS broker)
  static const String mqttBroker = 'spe4naz.online';
  static const int mqttPort = 8883; // MQTT over TLS (native clients)
  static const int mqttWssPort = 9002; // secure WebSocket (web clients)
  static const String mqttTopicPrefix = 'iot';
  static const String mqttUsername = 'app';
  // MQTT password is a live credential — never baked into the bundle.
  // The user enters it once in Настройки; it persists in local storage.
  static const String mqttPassword = '';

  // Signaling server write/read-token (register/delete/devices require it).
  // Live credential — entered by the user in Настройки, never baked in.
  static const String signalingToken = '';
  
  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // Data
  static const int maxDataPoints = 1000;
  static const Duration defaultTimeRange = Duration(hours: 24);
  
  /// Fallback defaults for known sensor types.
  /// Real units/names come dynamically from device modules (MetricInfo)
  /// via the Discovery Server / ESP32 REST API. These maps are used only
  /// when a module does not provide `metrics` metadata.
  static const Map<String, String> defaultSensorUnits = {
    'temperature': '°C',
    'humidity': '%',
    'pressure': 'hPa',
    'gas_resistance': 'Ω',
    'illuminance': 'lux',
  };

  /// Fallback display names, same rationale as [defaultSensorUnits].
  static const Map<String, String> defaultSensorNames = {
    'temperature': 'Температура',
    'humidity': 'Влажность',
    'pressure': 'Давление',
    'gas_resistance': 'Газ',
    'illuminance': 'Освещённость',
  };

  /// Common icon mapping for known metric keys.
  static IconData metricIcon(String key) {
    switch (key) {
      case 'temperature':
        return Icons.thermostat;
      case 'humidity':
        return Icons.water_drop;
      case 'pressure':
        return Icons.speed;
      case 'gas_resistance':
        return Icons.air;
      case 'illuminance':
        return Icons.light_mode;
      case 'co2':
        return Icons.eco;
      default:
        return Icons.sensors;
    }
  }
}
