import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../../models/device.dart';
import '../../models/sensor_data.dart';
import '../../models/alert.dart';
import '../../models/smart_rule.dart';

class ApiClient {
  late final Dio _dio;
  String _baseUrl;
  String _token;

  ApiClient({String? baseUrl, String token = ''})
      : _baseUrl = baseUrl ?? '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}',
        _token = token {
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: AppConfig.connectionTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token.isNotEmpty)
          'Authorization': 'Bearer $_token',
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
    ));
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  /// Updates the bearer token at runtime (settings change). Empty clears it.
  void setToken(String token) {
    _token = token;
    if (token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // Devices
  Future<List<Device>> getDevices() async {
    final response = await _dio.get('/devices');
    return (response.data as List)
        .map((json) => Device.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Device> getDevice(String id) async {
    final response = await _dio.get('/devices/$id');
    return Device.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Device> createDevice(Map<String, dynamic> data) async {
    final response = await _dio.post('/devices', data: data);
    return Device.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Device> updateDevice(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/devices/$id', data: data);
    return Device.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteDevice(String id) async {
    await _dio.delete('/devices/$id');
  }

  // Sensors
  Future<List<SensorData>> getSensorData(
    String deviceId,
    String sensorType, {
    DateTime? from,
    DateTime? to,
    String? interval,
  }) async {
    final queryParams = <String, dynamic>{};
    if (from != null) queryParams['from'] = from.toIso8601String();
    if (to != null) queryParams['to'] = to.toIso8601String();
    if (interval != null) queryParams['interval'] = interval;

    final response = await _dio.get(
      '/devices/$deviceId/sensors/$sensorType/data',
      queryParameters: queryParams,
    );
    return (response.data as List)
        .map((json) => SensorData.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<SensorDataSeries> getSensorDataSeries(
    String deviceId,
    String sensorType, {
    DateTime? from,
    DateTime? to,
    String? interval,
    String? unit,
  }) async {
    final data = await getSensorData(
      deviceId,
      sensorType,
      from: from,
      to: to,
      interval: interval,
    );

    return SensorDataSeries(
      sensorType: sensorType,
      unit: unit ?? AppConfig.defaultSensorUnits[sensorType] ?? '',
      points: data
          .map((d) => SensorDataPoint(
                timestamp: d.timestamp,
                value: d.getValue(sensorType) ?? 0,
              ))
          .toList(),
    );
  }

  // Modules
  Future<List<Module>> getModules(String deviceId) async {
    final response = await _dio.get('/devices/$deviceId/modules');
    return (response.data as List)
        .map((json) => Module.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendModuleCommand(
    String deviceId,
    String moduleId,
    Map<String, dynamic> command,
  ) async {
    await _dio.post(
      '/devices/$deviceId/modules/$moduleId/command',
      data: command,
    );
  }

  // Alerts
  Future<List<Alert>> getAlerts() async {
    final response = await _dio.get('/alerts');
    return (response.data as List)
        .map((json) => Alert.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Alert> createAlert(Map<String, dynamic> data) async {
    final response = await _dio.post('/alerts', data: data);
    return Alert.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Alert> updateAlert(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/alerts/$id', data: data);
    return Alert.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteAlert(String id) async {
    await _dio.delete('/alerts/$id');
  }

  // Smart-home rules
  Future<List<SmartRule>> getRules({String? deviceId}) async {
    final response = await _dio.get(
      '/rules',
      queryParameters: deviceId != null ? {'device_id': deviceId} : null,
    );
    return (response.data as List)
        .map((json) => SmartRule.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<SmartRule> createRule(Map<String, dynamic> data) async {
    final response = await _dio.post('/rules', data: data);
    return SmartRule.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SmartRule> updateRule(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/rules/$id', data: data);
    return SmartRule.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRule(String id) async {
    await _dio.delete('/rules/$id');
  }

  // Health
  Future<bool> checkHealth() async {
    try {
      await _dio.get('/health');
      return true;
    } catch (e) {
      return false;
    }
  }
}
