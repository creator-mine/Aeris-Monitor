import 'package:flutter/foundation.dart';
import '../../../core/api/signaling_api.dart';
import '../../../core/api/ota_api.dart';
import '../../../core/api/mqtt_client.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/api/lan_discovery.dart';
import '../../../core/api/lan_devices.dart';
import '../../../core/utils/version.dart';
import '../../../models/device.dart';
import '../../../models/firmware_manifest.dart';

class DevicesProvider extends ChangeNotifier {
  final SignalingApi _signalingApi;
  OtaApi? _otaApi;
  final MqttService? _mqtt;

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
  })  : _signalingApi = signalingApi,
        _otaApi = otaApi,
        _mqtt = mqtt;

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

  List<Device> get onlineDevices =>
      _devices.where((d) => d.isOnline).toList();

  List<Device> get offlineDevices =>
      _devices.where((d) => !d.isOnline).toList();

  Future<void> loadDevices() async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final registry = await _signalingApi.getDevices();
      final lan = await discoverLanDevices();
      _devices = mergeLanDevices(registry, lan);
    } catch (e) {
      // The cloud registry may be unreachable while the device is still on
      // the same Wi-Fi: fall back to local discovery.
      final lan = await discoverLanDevices();
      _devices = mergeLanDevices(const [], lan);
      if (_devices.isEmpty) _error = e.toString();
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> refreshDevices() async {
    await Future.wait([loadDevices(), loadManifest()]);
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

    final baseUrl = device.httpBaseUrl;
    if (baseUrl != null) {
      try {
        final client = DirectDeviceClient(baseUrl: baseUrl);
        try {
          final result = await client.sendOtaCommand();
          final started = result?['status'] == 'started' || result?['ok'] == true;
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

    final baseUrl = device.httpBaseUrl;
    if (baseUrl != null) {
      try {
        final client = DirectDeviceClient(baseUrl: baseUrl);
        try {
          final result = await client.sendCommand('ota_rollback');
          final started = result?['status'] == 'started' || result?['ok'] == true;
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