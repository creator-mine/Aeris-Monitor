import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A device found by the UDP broadcast responder running on the ESP32.
class DiscoveredDevice {
  final String id;
  final String name;
  final String type;
  final String ip;
  final int port;
  final String firmware;
  final int uptime;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.ip,
    required this.port,
    required this.firmware,
    required this.uptime,
  });
}

const String _discoveryMagic = 'AERIS_DISCOVER_V1';
const int _discoveryPort = 8266;

/// Broadcasts a discovery probe on the local network and collects replies.
///
/// The ESP32 answers with its id, type, firmware and address, so the app can
/// talk to `http://<ip>/api/v1/...` without the cloud registry.
Future<List<DiscoveredDevice>> discoverLanDevices({
  Duration timeout = const Duration(seconds: 1),
}) async {
  final found = <String, DiscoveredDevice>{};
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;

  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final targets = await _broadcastTargets();
    final payload = utf8.encode(_discoveryMagic);

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket!.receive();
      if (datagram == null) return;
      try {
        final map = jsonDecode(utf8.decode(datagram.data));
        if (map is! Map) return;
        final id = (map['id'] ?? '').toString();
        if (id.isEmpty) return;
        final repliedIp = (map['ip'] ?? '').toString();
        final sourceIp = datagram.address.address;
        found[id] = DiscoveredDevice(
          id: id,
          name: (map['name'] ?? id).toString(),
          type: (map['type'] ?? '').toString(),
          ip: sourceIp.isNotEmpty ? sourceIp : repliedIp,
          port: (map['port'] as num?)?.toInt() ?? 80,
          firmware: (map['fw'] ?? '').toString(),
          uptime: (map['uptime'] as num?)?.toInt() ?? 0,
        );
      } catch (_) {
        // Ignore malformed replies from unrelated services.
      }
    });

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final target in targets) {
        try {
          socket.send(payload, target, _discoveryPort);
        } catch (_) {
          // A single interface may reject broadcast; keep the others.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } catch (_) {
    // Discovery is best-effort: a failure falls back to the cloud registry.
  } finally {
    await subscription?.cancel();
    socket?.close();
  }

  return found.values.toList();
}

Future<Set<InternetAddress>> _broadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final parts = address.address.split('.');
        if (parts.length == 4) {
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    }
  } catch (_) {
    // Keep the global broadcast address.
  }
  return targets.map((value) => InternetAddress(value)).toSet();
}
