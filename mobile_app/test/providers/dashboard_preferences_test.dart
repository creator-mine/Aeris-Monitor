import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

Device _device(String id, {required String status}) {
  return Device(
    id: id,
    name: id,
    type: 'esp32',
    status: status,
    lastSeen: DateTime(2026, 11, 18, 12),
    ip: '192.168.0.10',
  );
}

void main() {
  test('prefers an online device over a stale offline registry entry', () {
    final offline = _device('esp32c6_001', status: 'offline');
    final online = _device('esp32s3_001', status: 'online');

    expect(pickPreferredDevice([offline, online])?.id, online.id);
  });

  test('keeps the previous selection while it is still registered', () {
    final offline = _device('esp32c6_001', status: 'offline');
    final online = _device('esp32s3_001', status: 'online');

    expect(
      pickPreferredDevice([offline, online], previousId: offline.id)?.id,
      offline.id,
    );
  });

  test('falls back to the first device when every device is offline', () {
    final first = _device('esp32c6_001', status: 'offline');
    final second = _device('esp32s3_001', status: 'offline');

    expect(pickPreferredDevice([first, second])?.id, first.id);
    expect(pickPreferredDevice(const []), isNull);
  });
}
