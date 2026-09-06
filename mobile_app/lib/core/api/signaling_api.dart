import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../../models/device.dart';

/// Client for the Signaling Server (device discovery/registry only).
/// It never holds sensor data — it only lists online devices and where to
/// connect (ip/port), then clients talk to the ESP32 directly.
class SignalingApi {
  late final Dio _dio;
  String _baseUrl;

  SignalingApi({String? baseUrl})
      : _baseUrl = baseUrl ?? '${AppConfig.signalingUrl}${AppConfig.signalingApiVersion}' {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: AppConfig.connectionTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (AppConfig.signalingToken.isNotEmpty)
          'Authorization': 'Bearer ${AppConfig.signalingToken}',
      },
    ));
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  String get baseUrl => _baseUrl;

  /// List of registered devices with connection info (ip:port).
  Future<List<Device>> getDevices() async {
    final response = await _dio.get('/devices');
    return (response.data as List)
        .map((json) => Device.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Device?> getDevice(String id) async {
    try {
      final response = await _dio.get('/devices/$id');
      return Device.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<bool> removeDevice(String id) async {
    try {
      await _dio.delete('/devices/$id');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  Future<bool> checkHealth() async {
    try {
      await _dio.get('/health');
      return true;
    } catch (e) {
      return false;
    }
  }
}