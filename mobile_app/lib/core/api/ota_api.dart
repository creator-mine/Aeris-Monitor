import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../../models/firmware_manifest.dart';

/// Fetches the published firmware manifest from the public OTA site.
///
/// The site hosts per-device_type artifacts (see deploy/fw.ps1):
///   esp32-c3 -> /fw/version.json + /fw/main.bin          (legacy layout)
///   esp32-s3 -> /fw/version-esp32-s3.json + /fw/main_esp32-s3.bin
/// Unknown/other types fall back to the legacy esp32-c3 files.
class OtaApi {
  final Dio _dio;

  OtaApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: AppConfig.connectionTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
            ));

  /// Manifest path for a device type (accepts any spelling:
  /// "esp32-c3", "esp32s3", device.type from the registry).
  static String manifestPathFor(String? deviceType) {
    final normalized = normalizeDeviceType(deviceType);
    return normalized == 'esp32-s3'
        ? '/fw/version-esp32-s3.json'
        : '/fw/version.json';
  }

  /// Firmware binary path for a device type (for display/download).
  static String binaryPathFor(String? deviceType) {
    final normalized = normalizeDeviceType(deviceType);
    return normalized == 'esp32-s3' ? '/fw/main_esp32-s3.bin' : '/fw/main.bin';
  }

  /// Coerces any device-type spelling to the app's canonical selectors
  /// ("esp32-c3" / "esp32-s3"). Unknown input is passed through unchanged.
  static String normalizeDeviceType(String? deviceType) {
    final t = deviceType?.trim().toLowerCase() ?? '';
    if (t.contains('s3')) return 'esp32-s3';
    if (t.contains('c6')) return 'esp32-c6';
    if (t.contains('c3')) return 'esp32-c3';
    return t.isEmpty ? 'esp32-c3' : t;
  }

  Future<FirmwareManifest?> fetchManifest({String? deviceType}) async {
    try {
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}${manifestPathFor(deviceType)}',
      );
      return FirmwareManifest.tryParse(response.data);
    } catch (_) {
      return null;
    }
  }
}