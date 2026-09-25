String expectedChipNameFor(String deviceType) {
  final t = deviceType.toLowerCase();
  if (t.contains('c6')) return 'ESP32-C6';
  if (t.contains('s3')) return 'ESP32-S3';
  return 'ESP32-C3';
}