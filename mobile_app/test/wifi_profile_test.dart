import 'package:aeris/models/wifi_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Wi-Fi status with profiles', () {
    final status = WifiStatus.fromJson({
      'connected': true,
      'id': 2,
      'ssid': 'Home',
      'rssi': -54,
      'ip': '192.168.0.10',
      'manual': true,
      'manual_id': 2,
      'used': 2,
      'max': 8,
      'profiles': [
        {'id': 2, 'ssid': 'Home', 'priority': 1, 'enabled': true, 'connected': true, 'rssi': -54},
        {'id': 5, 'ssid': 'Dacha', 'priority': 2, 'enabled': false, 'connected': false},
      ],
    });

    expect(status.connected, isTrue);
    expect(status.ssid, 'Home');
    expect(status.manual, isTrue);
    expect(status.used, 2);
    expect(status.max, 8);
    expect(status.profiles.length, 2);
    expect(status.profiles[1].ssid, 'Dacha');
    expect(status.profiles[1].enabled, isFalse);
    expect(status.profiles[1].rssi, isNull);
  });

  test('parses scan results and tolerates missing fields', () {
    final entry = WifiScanEntry.fromJson({
      'ssid': 'Guest',
      'rssi': -71,
      'secure': true,
    });
    expect(entry.ssid, 'Guest');
    expect(entry.rssi, -71);
    expect(entry.secure, isTrue);
    expect(entry.channel, 0);
    expect(entry.bssid, '');
  });
}
