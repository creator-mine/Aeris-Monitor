/// Web build: UDP broadcast is unavailable, so devices are resolved through
/// the signaling registry instead.
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

Future<List<DiscoveredDevice>> discoverLanDevices({
  Duration timeout = const Duration(seconds: 1),
}) async {
  return const [];
}
