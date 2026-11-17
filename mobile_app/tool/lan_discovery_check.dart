import 'package:aeris/core/api/lan_discovery.dart';

/// Manual LAN check: run on a desktop connected to the same Wi-Fi as the
/// ESP32 to confirm that discovery works without the cloud server.
///
///   C:\flutter\flutter\bin\dart.bat run tool/lan_discovery_check.dart
Future<void> main() async {
  final devices = await discoverLanDevices(timeout: const Duration(seconds: 2));
  if (devices.isEmpty) {
    print('no devices found');
    return;
  }
  for (final device in devices) {
    print('${device.id}  ${device.name}  http://${device.ip}:${device.port}'
        '  fw=${device.firmware}  uptime=${device.uptime}s');
  }
}
