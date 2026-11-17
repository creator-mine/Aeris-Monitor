import 'dart:convert';
import 'package:dio/dio.dart';

/// Client for the firmware's provisioning page.
///
/// A controller without saved Wi-Fi starts its own access point
/// (`Aeris-Setup-XXXX`, open, ~5 minutes) and serves the setup page on
/// http://192.168.4.1. Saving from the app posts to the same `/wifi/save`
/// endpoint that the page's form uses, so the phone does not need a browser.
class ProvisioningApi {
  static const String defaultBaseUrl = 'http://192.168.4.1';

  final Dio _dio;

  ProvisioningApi({String baseUrl = defaultBaseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 8),
              validateStatus: (_) => true,
            ));

  /// True when the setup page answers, i.e. the phone is on the device's AP.
  Future<bool> probe() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Saves Wi-Fi (and optionally the MQTT login) on the device.
  ///
  /// Returns `null` on success, otherwise a short reason: `missing_ssid`,
  /// `nvs_write_failed`, `no_connection`, `HTTP <code>`.
  Future<String?> save({
    required String ssid,
    required String password,
    String mqttUser = '',
    String mqttPassword = '',
  }) async {
    try {
      final response = await _dio.post(
        '/wifi/save',
        data: jsonEncode({
          'ssid': ssid,
          'password': password,
          'mqtt_user': mqttUser,
          'mqtt_password': mqttPassword,
        }),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = response.data;
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        return null;
      }
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return 'HTTP ${response.statusCode}';
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'no_connection';
      }
      return e.message ?? 'network_error';
    }
  }
}
