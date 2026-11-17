import 'package:aeris/core/api/lan_devices.dart';
import 'package:aeris/core/api/lan_discovery.dart';
import 'package:aeris/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Device registryDevice({String ip = ''}) => Device(
        id: 'esp32c6_001',
        name: 'Main Controller C6',
        type: 'esp32c6',
        status: ip.isEmpty ? 'offline' : 'online',
        lastSeen: DateTime(2026),
        ip: ip,
        port: 80,
        firmwareVersion: '1.2.12',
      );

  const lan = DiscoveredDevice(
    id: 'esp32c6_001',
    name: 'Main Controller C6',
    type: 'esp32c6',
    ip: '192.168.0.117',
    port: 80,
    firmware: '1.3.0',
    uptime: 42,
  );

  test('LAN discovery fills a missing registry IP', () {
    final merged = mergeLanDevices([registryDevice()], [lan]);
    expect(merged, hasLength(1));
    expect(merged.single.ip, '192.168.0.117');
    expect(merged.single.isOnline, true);
    expect(merged.single.firmwareVersion, '1.3.0');
  });

  test('LAN discovery adds a device missing from the registry', () {
    const other = DiscoveredDevice(
      id: 'esp32c3_002',
      name: 'Living room',
      type: 'esp32c3',
      ip: '192.168.0.118',
      port: 80,
      firmware: '1.3.0',
      uptime: 5,
    );
    final merged = mergeLanDevices([], [other]);
    expect(merged, hasLength(1));
    expect(merged.single.id, 'esp32c3_002');
    expect(merged.single.status, 'online');
  });

  test('registry data wins for name and sensors', () {
    final merged = mergeLanDevices([registryDevice(ip: '10.0.0.5')], [lan]);
    expect(merged.single.name, 'Main Controller C6');
    expect(merged.single.ip, '192.168.0.117');
  });
}
