/// Helpers for firmware artifact names. They are intentionally pure so the
/// same rules are used by the downloader, the provider and the tests.
library;

final RegExp _versionRe = RegExp(r'(\d+\.\d+\.\d+)');

/// Returns the semantic version embedded in a file or asset name, e.g.
/// `iot-modular-esp32c6-v1.3.2.bin` -> `1.3.2`.
String? firmwareVersionFromName(String name) {
  final match = _versionRe.firstMatch(name);
  return match?.group(1);
}

/// Detects the board type from a firmware artifact name.
///
/// Only the ESP32 controller images are supported: classic (`esp32`,
/// `esp32dev`), C3 (`esp32c3`, `esp32-c3`), C6 (`esp32c6`, `esp32-c6`) and
/// S3 (`esp32s3`, `esp32-s3`). Generic names such as `main.bin`/`firmware.bin`
/// return null so the caller's selected board is used.
String? firmwareDeviceTypeFromName(String name) {
  final lower = name.toLowerCase();

  // Check S3/C6 before C3: "esp32s3" does not contain "c3", but keeping the
  // order explicit makes the intent obvious and avoids future regressions.
  if (lower.contains('esp32s3') ||
      lower.contains('esp32-s3') ||
      RegExp(r'(^|[^a-z0-9])s3([^a-z0-9]|$)').hasMatch(lower)) {
    return 'esp32-s3';
  }
  if (lower.contains('esp32c6') ||
      lower.contains('esp32-c6') ||
      RegExp(r'(^|[^a-z0-9])c6([^a-z0-9]|$)').hasMatch(lower)) {
    return 'esp32-c6';
  }
  if (lower == 'main.bin' || lower == 'firmware.bin') {
    // Generic PlatformIO output: the caller's selected board is authoritative.
    return null;
  }
  if (lower.contains('esp32c3') ||
      lower.contains('esp32-c3') ||
      RegExp(r'(^|[^a-z0-9])c3([^a-z0-9]|$)').hasMatch(lower)) {
    return 'esp32-c3';
  }
  // Classic ESP32: "esp32dev", "esp32-classic", or a standalone "esp32"
  // token in names like "aeris-1.6.0-esp32.bin" / "main_esp32.bin".
  if (lower.contains('esp32dev') ||
      lower.contains('esp32-classic') ||
      RegExp(r'(^|[^a-z0-9])esp32([^a-z0-9]|$)').hasMatch(lower)) {
    return 'esp32';
  }
  return null;
}

/// A filesystem-safe filename for the staged copy.
String safeFirmwareFileName(String name) {
  var base = name.split(RegExp(r'[/\\]')).last.trim();
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (base.isEmpty) base = 'firmware.bin';
  if (!base.toLowerCase().endsWith('.bin')) base = '$base.bin';
  if (base.length > 100) {
    base = '${base.substring(0, 90)}.bin';
  }
  return base;
}
