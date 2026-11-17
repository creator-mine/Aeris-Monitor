import '../../models/device.dart';
import 'lan_discovery.dart';

/// Applies LAN discovery data to a device known from the registry.
Device applyLanDiscovery(Device device, DiscoveredDevice lan) {
  return Device(
    id: device.id,
    name: device.name.isNotEmpty ? device.name : lan.name,
    type: device.type.isNotEmpty ? device.type : lan.type,
    status: 'online',
    lastSeen: DateTime.now(),
    ip: lan.ip,
    port: lan.port,
    sensors: device.sensors,
    modules: device.modules,
    firmwareVersion: lan.firmware.isNotEmpty ? lan.firmware : device.firmwareVersion,
  );
}

/// Creates a device entry for something that answered discovery but is missing
/// from the (possibly unreachable) cloud registry.
Device deviceFromLan(DiscoveredDevice lan) {
  return Device(
    id: lan.id,
    name: lan.name.isNotEmpty ? lan.name : lan.id,
    type: lan.type,
    status: 'online',
    lastSeen: DateTime.now(),
    ip: lan.ip,
    port: lan.port,
    firmwareVersion: lan.firmware,
  );
}

/// Merges registry devices with LAN-discovered ones, preferring the live
/// local address for devices that the registry reports without an IP.
List<Device> mergeLanDevices(
  List<Device> devices,
  List<DiscoveredDevice> discovered,
) {
  final byId = <String, Device>{for (final device in devices) device.id: device};
  for (final lan in discovered) {
    final existing = byId[lan.id];
    byId[lan.id] = existing == null
        ? deviceFromLan(lan)
        : applyLanDiscovery(existing, lan);
  }
  return byId.values.toList();
}
