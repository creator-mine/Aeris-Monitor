String expectedChipNameFor(String deviceType) {
  final t = deviceType.toLowerCase();
  if (t.contains('c6')) return 'ESP32-C6';
  if (t.contains('s3')) return 'ESP32-S3';
  if (t.contains('c3')) return 'ESP32-C3';
  if (t == 'esp32' || t.contains('esp32dev') || t.contains('esp32-classic')) {
    return 'ESP32';
  }
  return 'ESP32-C3';
}
