import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device.dart';
import '../config/app_config.dart';
import 'direct_device_client.dart';
import 'lan_discovery.dart';
import 'lan_devices.dart';

/// Resolves ESP32 boards without the cloud registry.
///
/// The app is expected to keep working when the internet is down: probe the
/// last known address, the device's own SoftAP address and UDP discovery, in
/// parallel. The cloud is only a convenience on top of this.
typedef LocalDeviceProbe = Future<Device?> Function(String host, int port);
typedef LocalDeviceScan = Future<List<DiscoveredDevice>> Function();

class LocalDeviceService {
  LocalDeviceService({
    LocalDeviceProbe? probe,
    LocalDeviceScan? scan,
    Future<SharedPreferences> Function()? preferences,
  })  : _probe = probe ?? probeDeviceHttp,
        _scan = scan ?? discoverLanDevices,
        _preferences = preferences ?? SharedPreferences.getInstance;

  final LocalDeviceProbe _probe;
  final LocalDeviceScan _scan;
  final Future<SharedPreferences> Function() _preferences;

  static const String lastIpKey = 'last_device_ip';
  static const String lastPortKey = 'last_device_port';
  static const String lastIdKey = 'last_device_id';
  static const String lastNameKey = 'last_device_name';
  static const String lastTypeKey = 'last_device_type';
  static const String lastFirmwareKey = 'last_device_firmware';

  /// The ESP32 SoftAP always uses 192.168.4.1. Probing it is harmless on a
  /// normal LAN: a router just answers with something that is not an AERIS
  /// status document and the probe is discarded.
  static const String softApHost = '192.168.4.1';

  static const String offlineMessage =
      'Не удалось найти устройства. Подключите телефон к той же Wi-Fi-сети, '
      'что и плата, или укажите её адрес в настройках (например, 192.168.4.1).';

  /// Last known addresses first, then the SoftAP default. Duplicates removed.
  List<(String, int)> candidateHosts(SharedPreferences prefs) {
    final raw = <String>[];
    final manual = prefs.getString(AppConfig.deviceHostPrefKey)?.trim();
    if (manual != null && manual.isNotEmpty) raw.add(manual);

    final lastIp = prefs.getString(lastIpKey)?.trim();
    if (lastIp != null && lastIp.isNotEmpty) {
      final port = prefs.getInt(lastPortKey) ?? AppConfig.deviceHttpPort;
      raw.add('$lastIp:$port');
    }
    raw.add('$softApHost:${AppConfig.deviceHttpPort}');

    final seen = <String>{};
    final result = <(String, int)>[];
    for (final value in raw) {
      final parsed = _parseHost(value);
      if (parsed == null) continue;
      if (seen.add('${parsed.$1}:${parsed.$2}')) result.add(parsed);
    }
    return result;
  }

  /// Finds every locally reachable board. Never throws: an offline network
  /// simply returns an empty list.
  Future<List<Device>> discover({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    SharedPreferences? prefs;
    try {
      prefs = await _preferences();
    } catch (_) {
      // Without prefs we can still try the SoftAP address.
    }

    final candidates = prefs == null
        ? <(String, int)>[(softApHost, AppConfig.deviceHttpPort)]
        : candidateHosts(prefs);

    final scanFuture = _scan().catchError((Object error) {
      debugPrint('LAN discovery failed: $error');
      return <DiscoveredDevice>[];
    });

    final probes = candidates.map((candidate) {
      return _probe(candidate.$1, candidate.$2).catchError((Object error) {
        debugPrint('Probe ${candidate.$1}:${candidate.$2} failed: $error');
        return null;
      });
    });

    final probeResults = await Future.wait(probes).timeout(
      timeout,
      onTimeout: () => const <Device?>[],
    );

    List<DiscoveredDevice> discovered;
    try {
      discovered = await scanFuture.timeout(
        timeout,
        onTimeout: () => const <DiscoveredDevice>[],
      );
    } catch (_) {
      discovered = const [];
    }

    final byId = <String, Device>{};
    for (final device in probeResults.whereType<Device>()) {
      byId[device.id] = device;
    }
    for (final lan in discovered) {
      if (byId.containsKey(lan.id)) continue;
      byId[lan.id] = deviceFromLan(lan);
    }

    final devices = byId.values.toList();
    if (prefs != null) {
      for (final device in devices) {
        await remember(device, prefs: prefs);
      }
    }
    return devices;
  }

  /// Caches the address that actually worked, so the next offline launch can
  /// connect even before UDP discovery finishes.
  Future<void> remember(Device device, {SharedPreferences? prefs}) async {
    if (device.ip.isEmpty) return;
    try {
      final store = prefs ?? await _preferences();
      await store.setString(lastIpKey, device.ip);
      await store.setInt(lastPortKey, device.port);
      await store.setString(lastIdKey, device.id);
      await store.setString(lastNameKey, device.name);
      await store.setString(lastTypeKey, device.type);
      final firmware = device.firmwareVersion;
      if (firmware != null && firmware.isNotEmpty) {
        await store.setString(lastFirmwareKey, firmware);
      }
    } catch (error) {
      debugPrint('Could not cache the device address: $error');
    }
  }

  /// One unauthenticated status request is enough to identify a board.
  static Future<Device?> probeDeviceHttp(String host, int port) async {
    final client = DirectDeviceClient(
      baseUrl: 'http://$host:$port',
      connectTimeout: const Duration(milliseconds: 700),
      receiveTimeout: const Duration(milliseconds: 1200),
    );
    try {
      final status = await client.getStatus();
      final id = (status['device_id'] ?? '').toString().trim();
      if (id.isEmpty) return null;

      List<Module> modules = const [];
      try {
        modules = await client.getModules().timeout(
              const Duration(milliseconds: 700),
              onTimeout: () => const <Module>[],
            );
      } catch (_) {
        // Status alone is enough to open the board; the WebSocket pushes the
        // module list immediately after connecting.
      }

      final name = (status['device_name'] ?? id).toString().trim();
      final type = (status['device_type'] ?? '').toString().trim();
      final firmware = (status['firmware'] ?? '').toString().trim();
      return Device(
        id: id,
        name: name.isEmpty ? id : name,
        type: type,
        status: 'online',
        lastSeen: DateTime.now(),
        ip: host,
        port: port,
        modules: modules,
        firmwareVersion: firmware.isEmpty ? null : firmware,
      );
    } catch (error) {
      debugPrint('Local probe $host:$port failed: $error');
      return null;
    } finally {
      client.dispose();
    }
  }

  static (String, int)? _parseHost(String value) {
    var text = value.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    try {
      final uri = Uri.parse(text);
      if (uri.host.isEmpty) return null;
      return (uri.host, uri.hasPort ? uri.port : AppConfig.deviceHttpPort);
    } catch (_) {
      return null;
    }
  }
}
