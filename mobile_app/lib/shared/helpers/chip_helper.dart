String expectedChipNameFor(String deviceType) {
  return deviceType.toLowerCase().contains('c6') ? 'ESP32-C6' : 'ESP32-C3';
}