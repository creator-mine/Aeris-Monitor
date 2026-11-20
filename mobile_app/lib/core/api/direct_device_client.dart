import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/device.dart';
import '../../models/sensor_data.dart';
import '../../models/log_entry.dart';

/// Direct HTTP client for a single ESP32 device.
/// Connects straight to the device (http://<ip>:<port>/api/v1/...) —
/// no broker, no server in the middle.
class DirectDeviceClient {
  final Dio _dio;

  DirectDeviceClient({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ));

  Future<Map<String, dynamic>> getSensors() async {
    final response = await _dio.get('/api/v1/sensors');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStatus() async {
    final response = await _dio.get('/api/v1/status');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Module>> getModules() async {
    final response = await _dio.get('/api/v1/modules');
    return (response.data as List)
        .map((json) => Module.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getSdInfo() async {
    final response = await _dio.get('/api/v1/sd/info');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWifiStatus() async {
    final response = await _dio.get('/api/v1/wifi');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> scanWifi({bool refresh = false}) async {
    final response = await _dio.get(
      '/api/v1/wifi/scan',
      queryParameters: refresh ? {'refresh': 1} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> sendWifiCommand(
    String command, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final response = await _dio.post(
      '/api/v1/command',
      data: jsonEncode({'command': command, ...extra}),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return response.data as Map<String, dynamic>?;
  }

  /// History from the device's SD card.
  Future<SensorDataSeries> getHistory(
    String sensorType, {
    String? unit,
    DateTime? since,
    int limit = 1000,
  }) async {
    final query = <String, dynamic>{
      'type': sensorType,
      'limit': limit,
    };
    if (since != null) query['since'] = since.millisecondsSinceEpoch;

    final response = await _dio.get(
      '/api/v1/sensors/history',
      queryParameters: query,
    );

    final data = response.data as Map<String, dynamic>;
    final points = (data['points'] as List<dynamic>? ?? [])
        .map((p) {
          final map = p as Map<String, dynamic>;
          return SensorDataPoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                (map['timestamp'] as num).toInt()),
            value: (map['value'] as num).toDouble(),
          );
        })
        .toList();

    return SensorDataSeries(
      sensorType: sensorType,
      unit: unit ?? '',
      points: points,
    );
  }

  /// Device logs from the in-memory ring buffer.
  Future<List<LogEntry>> getLogs({int? limit}) async {
    final query = <String, dynamic>{};
    if (limit != null) query['limit'] = limit;

    final response = await _dio.get('/api/v1/logs', queryParameters: query);

    final data = response.data;
    if (data is! List) return const [];
    return data
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Send a command: "restart" | "read_sensor" | "rescan" | "ota".
  Future<Map<String, dynamic>?> sendCommand(String command) async {
    final response = await _dio.post(
      '/api/v1/command',
      data: jsonEncode({'command': command}),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return response.data as Map<String, dynamic>?;
  }

  /// Ask the device to pull and apply the latest published firmware (OTA).
  Future<Map<String, dynamic>?> sendOtaCommand({bool force = false}) async {
    final response = await _dio.post(
      '/api/v1/command',
      data: jsonEncode({
        'command': 'ota',
        if (force) 'force': true,
      }),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return response.data as Map<String, dynamic>?;
  }

  /// Save new WiFi credentials on the device and restart it.
  Future<Map<String, dynamic>?> setWifi(String ssid, String password) async {
    final response = await _dio.post(
      '/api/v1/command',
      data: jsonEncode({
        'command': 'wifi_set',
        'ssid': ssid,
        'password': password,
      }),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return response.data as Map<String, dynamic>?;
  }

  void dispose() {
    _dio.close(force: true);
  }
}