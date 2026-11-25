import 'package:aeris/core/api/lan_discovery.dart';
import 'package:aeris/core/api/local_device_service.dart';
import 'package:aeris/models/device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _device(String id, {String ip = '10.0.0.5'}) {
  return Device(
    id: id,
    name: 'Controller $id',
    type: 'esp32s3',
    status: 'online',
    lastSeen: DateTime(2026, 11, 25, 12),
    ip: ip,
    firmwareVersion: '1.4.1',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probes the cached address and remembers the working one', () async {
    SharedPreferences.setMockInitialValues({
      LocalDeviceService.lastIpKey: '10.0.0.5',
      LocalDeviceService.lastPortKey: 80,
    });
    final prefs = await SharedPreferences.getInstance();
    final probed = <String>[];

    final service = LocalDeviceService(
      preferences: () async => prefs,
      scan: () async => const <DiscoveredDevice>[],
      probe: (host, port) async {
        probed.add('$host:$port');
        return host == '10.0.0.5' ? _device('esp32s3_001') : null;
      },
    );

    final devices = await service.discover();

    expect(devices.single.id, 'esp32s3_001');
    expect(probed, contains('10.0.0.5:80'));
    expect(probed, contains('192.168.4.1:80'));
    expect(
      prefs.getString(LocalDeviceService.lastIdKey),
      'esp32s3_001',
    );
  });

  test('accepts a manual host with an explicit port', () async {
    SharedPreferences.setMockInitialValues({
      'device_host': 'http://10.0.0.7:8080',
    });
    final prefs = await SharedPreferences.getInstance();
    String? seenHost;
    int? seenPort;

    final service = LocalDeviceService(
      preferences: () async => prefs,
      scan: () async => const <DiscoveredDevice>[],
      probe: (host, port) async {
        if (host == '10.0.0.7') {
          seenHost = host;
          seenPort = port;
          return _device('esp32c6_001', ip: host);
        }
        return null;
      },
    );

    final devices = await service.discover();

    expect(devices.single.id, 'esp32c6_001');
    expect(seenHost, '10.0.0.7');
    expect(seenPort, 8080);
  });

  test('keeps a UDP-discovered device when HTTP probing is unavailable',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final service = LocalDeviceService(
      preferences: () async => prefs,
      scan: () async => const [
        DiscoveredDevice(
          id: 'esp32s3_001',
          name: 'S3',
          type: 'esp32s3',
          ip: '192.168.43.7',
          port: 80,
          firmware: '1.4.1',
          uptime: 120,
        ),
      ],
      probe: (_, __) async => null,
    );

    final devices = await service.discover();

    expect(devices.single.id, 'esp32s3_001');
    expect(devices.single.ip, '192.168.43.7');
    expect(devices.single.firmwareVersion, '1.4.1');
    expect(
      prefs.getString(LocalDeviceService.lastIpKey),
      '192.168.43.7',
    );
  });

  test('deduplicates a board found by both HTTP and UDP', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final service = LocalDeviceService(
      preferences: () async => prefs,
      scan: () async => const [
        DiscoveredDevice(
          id: 'esp32s3_001',
          name: 'S3 from UDP',
          type: 'esp32s3',
          ip: '192.168.43.7',
          port: 80,
          firmware: '1.4.1',
          uptime: 120,
        ),
      ],
      probe: (_, __) async => _device('esp32s3_001'),
    );

    final devices = await service.discover();

    expect(devices, hasLength(1));
    expect(devices.single.name, 'Controller esp32s3_001');
  });

  test('returns an empty list when nothing answers', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final service = LocalDeviceService(
      preferences: () async => prefs,
      scan: () async => const <DiscoveredDevice>[],
      probe: (_, __) async => null,
    );

    expect(await service.discover(), isEmpty);
  });
}
