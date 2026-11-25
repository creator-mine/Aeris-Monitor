import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../../core/api/signaling_api.dart';
import '../../../core/api/ota_api.dart';
import '../../../core/api/mqtt_client.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/api/lan_discovery.dart';
import '../../../core/api/local_device_service.dart';
import '../../../core/config/connection_mode.dart';
import '../../../core/utils/version.dart';
import '../../../models/device.dart';
import '../../../models/firmware_manifest.dart';
import '../../../models/sd_card_info.dart';

class DevicesProvider extends ChangeNotifier {
  final SignalingApi _signalingApi;
  OtaApi? _otaApi;
  final MqttService? _mqtt;
  final LocalDeviceService _localDevices;

  List<Device> _devices = [];
  bool _isLoading = false;
  String? _error;
  bool _disposed = false;

  /// Published manifests keyed by canonical device type ("esp32-c3",
  /// "esp32-c6", "esp32-s3"), each fetched from its own /fw/version*.json.
  final Map<String, FirmwareManifest> _manifests = {};
  bool _isLoadingManifest = false;
  String? _manifestError;

  DevicesProvider({
    required SignalingApi signalingApi,
    OtaApi? otaApi,
    MqttService? mqtt,
    Future<List<DiscoveredDevice>> Function()? discoverLan,
    LocalDeviceService? localDevices,
  })  : _signalingApi = signalingApi,
        _otaApi = otaApi,
        _mqtt = mqtt,
        _localDevices = localDevices ??
            LocalDeviceService(
              scan: discoverLan ?? discoverLanDevices,
              // An injected scan is a deterministic test hook: keep the HTTP
              // probes out of unit tests.
              probe: discoverLan == null ? null : (_, __) async => null,
            );

  List<Device> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasManifest => _manifests.isNotEmpty;
  bool get isLoadingManifest => _isLoadingManifest;
  String? get manifestError => _manifestError;

  /// Rebuilds the OTA client after the user changes the OTA host in settings.
  void setOtaBaseUrl(String url) {
    _otaApi = OtaApi(baseUrl: url);
    _manifests.clear();
    _manifestError = null;
    _safeNotify();
  }

  /// The published manifest for the device's own type. Unknown/custom types
  /// fall back to the legacy esp32-c3 manifest; a known type that failed to
  /// load returns null instead of comparing against a different chip.
  FirmwareManifest? manifestFor(Device device) {
    final type = OtaApi.normalizeDeviceType(device.type);
    final exact = _manifests[type];
    if (exact != null) return exact;
    const known = {'esp32-c3', 'esp32-c6', 'esp32-s3'};
    if (known.contains(type)) return null;
    return _manifests['esp32-c3'];
  }

  String? get latestPublishedVersion {
    if (_manifests.isEmpty) return null;
    // Prefer the C3 manifest; otherwise return a deterministic entry rather
    // than whichever type happened to be fetched first.
    return (_manifests['esp32-c3'] ?? _manifests.values.first).version;
  }

  List<Device> get onlineDevices => _devices.where((d) => d.isOnline).toList();

  List<Device> get offlineDevices =>
      _devices.where((d) => !d.isOnline).toList();

  Future<void> loadDevices() async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    // The registry is a convenience: a LAN-only phone must not wait for DNS.
    Object? cloudError;
    final registryFuture =
        _signalingApi.getDevices().onError((error, stackTrace) {
      // Attach the handler before the local scan so the failure is never
      // reported as an unhandled async error.
      cloudError = error;
      return const <Device>[];
    });

    List<Device> local = const [];
    if (LanPolicy.enabled) {
      try {
        local = await _localDevices.discover();
      } catch (error) {
        debugPrint('Local device discovery failed: $error');
      }
    }
    if (_disposed) return;

    if (local.isNotEmpty) {
      _devices = _mergeDevices(_devices, local);
      _isLoading = false;
      _safeNotify();
    }

    List<Device> registry = const [];
    try {
      registry = await registryFuture.timeout(const Duration(seconds: 4));
    } catch (error) {
      cloudError = error;
    }
    if (_disposed) return;

    if (registry.isNotEmpty) {
      _devices = _mergeDevices(registry, _devices);
    }
    if (_devices.isEmpty) {
      _error = LocalDeviceService.offlineMessage;
      if (cloudError != null) {
        debugPrint('Cloud registry unavailable: $cloudError');
      }
    } else {
      _error = null;
    }
    _isLoading = false;
    if (!_disposed) _safeNotify();
  }

  List<Device> _mergeDevices(List<Device> registry, List<Device> local) {
    final byId = <String, Device>{
      for (final device in registry) device.id: device
    };
    for (final device in local) {
      final existing = byId[device.id];
      if (existing == null) {
        byId[device.id] = device;
        continue;
      }
      byId[device.id] = existing.copyWith(
        name: device.name.isNotEmpty ? device.name : existing.name,
        type: device.type.isNotEmpty ? device.type : existing.type,
        status: device.isOnline ? 'online' : existing.status,
        lastSeen: device.lastSeen,
        ip: device.ip.isNotEmpty ? device.ip : existing.ip,
        port: device.port,
        modules: device.modules.isNotEmpty ? device.modules : existing.modules,
        firmwareVersion: device.firmwareVersion ?? existing.firmwareVersion,
      );
    }
    return byId.values.toList();
  }

  Future<void> refreshDevices() async {
    await Future.wait([loadDevices(), loadManifest()]);
  }

  bool _isRefreshingPresence = false;

  /// Quietly refreshes only the online/offline status from the registry.
  /// The full [loadDevices] also rescans the LAN and replaces the whole list,
  /// which is too heavy for a periodic presence tick and would drop devices
  /// whenever the cloud registry is momentarily unreachable.
  Future<void> refreshPresence() async {
    if (_disposed || _isRefreshingPresence) return;
    _isRefreshingPresence = true;
    try {
      final registry =
          await _signalingApi.getDevices().timeout(const Duration(seconds: 5));
      if (_disposed) return;

      final freshById = {for (final device in registry) device.id: device};
      var changed = false;

      for (var i = 0; i < _devices.length; i++) {
        final fresh = freshById[_devices[i].id];
        if (fresh == null) continue;
        final current = _devices[i];
        if (current.status == fresh.status &&
            current.lastSeen == fresh.lastSeen) {
          continue;
        }
        _devices[i] = current.copyWith(
          status: fresh.status,
          lastSeen: fresh.lastSeen,
          ip: fresh.ip.isNotEmpty ? fresh.ip : null,
          port: fresh.port,
          firmwareVersion: fresh.firmwareVersion,
        );
        changed = true;
      }

      // A device registered after the list was loaded should appear too.
      for (final fresh in registry) {
        if (_devices.any((device) => device.id == fresh.id)) continue;
        _devices.add(fresh);
        changed = true;
      }

      if (changed) _safeNotify();
    } catch (_) {
      // Keep the last known list; the next tick retries.
    } finally {
      _isRefreshingPresence = false;
    }
  }

  /// Fetches the real published firmware manifests from the OTA site
  /// for every known device type (plus the types currently in the registry).
  Future<void> loadManifest() async {
    if (_isLoadingManifest) return;
    _isLoadingManifest = true;
    _manifestError = null;
    notifyListeners();

    final api = _otaApi;
    if (api == null) {
      _isLoadingManifest = false;
      _safeNotify();
      return;
    }

    final types = <String>{'esp32-c3', 'esp32-c6', 'esp32-s3'};
    for (final device in _devices) {
      types.add(OtaApi.normalizeDeviceType(device.type));
    }

    try {
      for (final type in types) {
        final manifest = await api.fetchManifest(deviceType: type);
        if (_disposed) return;
        if (manifest != null) {
          _manifests[type] = manifest;
        }
      }
      if (_manifests.isEmpty) {
        _manifestError =
            'Не удалось получить опубликованную версию устройства.';
      }
    } catch (e) {
      _manifestError = e.toString();
    } finally {
      if (!_disposed) {
        _isLoadingManifest = false;
        _safeNotify();
      }
    }
  }

  /// True when the device runs an older firmware than the published one.
  bool isOutdated(Device device) {
    final published = manifestFor(device)?.version;
    if (published == null || published.isEmpty) return false;
    final running = device.firmwareVersion;
    if (running == null || running.isEmpty) return false;
    return compareVersions(running, published) < 0;
  }

  /// Sends the OTA pull command to the device. Returns a human-readable
  /// result to surface in the UI.
  Future<String> sendOtaCommand(Device device) async {
    if (!device.isOnline) {
      return 'Устройство ${device.name} не в сети';
    }

    final mqtt = _mqtt;
    if (mqtt != null && mqtt.isConnected) {
      mqtt.publishCommand(device.id, {
        'type': 'command',
        'command': 'ota',
      });
      return 'Команда ОТА отправлена через MQTT — устройство скачает прошивку и перезагрузится';
    }

    final baseUrl = LanPolicy.enabled ? device.httpBaseUrl : null;
    if (baseUrl != null) {
      try {
        final client = DirectDeviceClient(baseUrl: baseUrl);
        try {
          final result = await client.sendOtaCommand();
          final started =
              result?['status'] == 'started' || result?['ok'] == true;
          if (started) {
            return 'Команда ОТА отправлена напрямую — устройство скачает прошивку и перезагрузится';
          }
          if (result?['error'] == 'ota_busy') {
            return 'Обновление уже запущено на устройстве';
          }
          return 'Устройство вернуло ошибку: ${result ?? 'нет ответа'}';
        } finally {
          client.dispose();
        }
      } catch (e) {
        return 'Не удалось связаться с устройством напрямую: $e';
      }
    }

    return 'Нет связи с устройством (MQTT не подключён, IP неизвестен)';
  }

  /// Asks the device to reboot into the previously running app partition.
  /// Returns a human-readable result to surface in the UI.
  Future<String> sendOtaRollbackCommand(Device device) async {
    if (!device.isOnline) {
      return 'Устройство ${device.name} не в сети';
    }

    final mqtt = _mqtt;
    if (mqtt != null && mqtt.isConnected) {
      mqtt.publishCommand(device.id, {
        'type': 'command',
        'command': 'ota_rollback',
      });
      return 'Команда отката отправлена через MQTT — устройство загрузит предыдущую прошивку и перезагрузится';
    }

    final baseUrl = LanPolicy.enabled ? device.httpBaseUrl : null;
    if (baseUrl != null) {
      try {
        final client = DirectDeviceClient(baseUrl: baseUrl);
        try {
          final result = await client.sendCommand('ota_rollback');
          final started =
              result?['status'] == 'started' || result?['ok'] == true;
          if (started) {
            return 'Команда отката отправлена напрямую — устройство загрузит предыдущую прошивку и перезагрузится';
          }
          if (result?['error'] == 'rollback_failed') {
            return 'Не удалось переключить на предыдущую прошивку';
          }
          return 'Устройство вернуло ошибку: ${result ?? 'нет ответа'}';
        } finally {
          client.dispose();
        }
      } catch (e) {
        return 'Не удалось связаться с устройством напрямую: $e';
      }
    }

    return 'Нет связи с устройством (MQTT не подключён, IP неизвестен)';
  }

  /// Renames a device in the server registry and keeps the local module list
  /// (the registry does not store modules, only connection metadata).
  Future<Device?> renameDevice(Device device, String name) async {
    try {
      final updated = await _signalingApi.renameDevice(device.id, name.trim());
      if (_disposed) return updated;
      final merged = updated.copyWith(
        modules: device.modules,
        sensors: updated.sensors.isEmpty ? device.sensors : updated.sensors,
      );
      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index >= 0) _devices[index] = merged;
      _safeNotify();
      return merged;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return null;
    }
  }

  Future<bool> deleteDevice(String id) async {
    try {
      final removed = await _signalingApi.removeDevice(id);
      if (_disposed) return removed;
      if (removed) {
        _devices.removeWhere((d) => d.id == id);
      }
      _safeNotify();
      return removed;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Device? getDeviceById(String id) {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index == -1) return null;
    return _devices[index];
  }

  /// Last status frame received over MQTT, for diagnostics without LAN.
  Map<String, dynamic>? latestStatusFor(String deviceId) {
    final payload = _mqtt?.latestStatus(
      deviceId,
      maxAge: const Duration(minutes: 10),
    );
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// SD-card state from the latest MQTT status, used as a fallback when the
  /// device is reachable only through the broker.
  SdCardInfo? sdCardFor(String deviceId) {
    final status = latestStatusFor(deviceId);
    if (status == null) return null;
    return SdCardInfo.tryFromStatus(status);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
