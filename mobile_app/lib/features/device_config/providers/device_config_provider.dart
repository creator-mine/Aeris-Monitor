import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/serial/serial_service.dart';
import '../../../core/api/ota_api.dart';
import '../../../core/utils/version.dart';
import '../../../models/log_entry.dart';
import '../../../models/firmware_manifest.dart';

/// Provider for the "Настройка" tab.
///
/// Talks to the ESP32 over a USB COM port (serial_cmd protocol on the
/// firmware side): lists ports, reads device info / logs / sensors and
/// configures WiFi credentials. Includes a real firmware-version check
/// against the published manifest.
class DeviceConfigProvider extends ChangeNotifier {
  final SerialService _serial;
  OtaApi? _otaApi;

  Timer? _logTimer;
  Timer? _statusTimer;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  List<String> _ports = [];
  String? _selectedPort;
  List<LogEntry> _logs = [];
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _status;
  String? _error;
  late StreamSubscription<Map<String, dynamic>> _respSub;
  late StreamSubscription<String> _errorSub;

  FirmwareManifest? _manifest;
  bool _isCheckingManifest = false;
  bool _manifestCheckQueued = false;
  String? _manifestError;
  bool _isSendingOta = false;

  DeviceConfigProvider({SerialService? serial, OtaApi? otaApi})
      : _serial = serial ?? SerialService(),
        _otaApi = otaApi {
    _respSub = _serial.responses.listen(_onResponse);
    _errorSub = _serial.errors.listen((e) {
      _error = e;
      notifyListeners();
    });
  }

  /// True while the COM port is being opened (the worker isolate may need a
  /// second or two on a fresh USB connection).
  bool _isConnecting = false;

  List<String> get ports => _ports;
  String? get selectedPort => _selectedPort;
  bool get isConnected => _serial.isConnected;
  bool get isConnecting => _isConnecting;
  /// True while the board is rebooting and the port is being reopened.
  bool get isReconnecting => _isReconnecting;
  List<LogEntry> get logs => _logs;
  Map<String, dynamic>? get info => _info;
  Map<String, dynamic>? get status => _status;
  String? get error => _error;
  String? get firmwareVersion => info?['firmware'] as String?;
  FirmwareManifest? get manifest => _manifest;
  bool get isCheckingManifest => _isCheckingManifest;
  String? get manifestError => _manifestError;
  bool get isSendingOta => _isSendingOta;
  String? get latestPublishedVersion => _manifest?.version;

  bool get isOutdated => freshness == FirmwareFreshness.outdated;

  FirmwareFreshness get freshness =>
      firmwareFreshness(firmwareVersion, _manifest?.version);

  /// Point the version checker at the configured OTA host.
  void setOtaBaseUrl(String url) {
    _otaApi = OtaApi(baseUrl: url);
    _manifest = null;
    _manifestError = null;
    notifyListeners();
  }

  /// Refresh the list of available COM ports (called on tab open / refresh).
  Future<void> loadDevices() async {
    await refreshPorts();
    await checkManifest();
  }

  Future<void> refreshPorts() async {
    _ports = SerialService.listPorts();
    notifyListeners();
  }

  Future<bool> connect(String portName) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _selectedPort = portName;
    _error = null;
    notifyListeners();
    try {
      if (!await _serial.connect(portName)) {
        _selectedPort = null;
        return false;
      }
      // Give the ESP32 a moment to finish booting before the first command.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      _serial.requestInfo();
      _serial.requestStatus();
      startLogStream();
      _startStatusPoll();
      return _serial.isConnected;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    stopLogStream();
    _statusTimer?.cancel();
    _statusTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    await _serial.disconnect();
    _logs.clear();
    _info = null;
    _status = null;
    notifyListeners();
  }

  void startLogStream() {
    stopLogStream();
    _serial.requestLogs();
    _logTimer = Timer.periodic(
        const Duration(seconds: 2), (_) => _serial.requestLogs());
  }

  void stopLogStream() {
    _logTimer?.cancel();
    _logTimer = null;
  }

  /// Keeps uptime / Wi-Fi / RSSI fresh and notices a board that went away.
  void _startStatusPoll() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_serial.isConnected) _serial.requestStatus();
    });
  }

  /// The device reboots itself after a Wi-Fi change, a manual restart or an
  /// OTA command. That re-enumerates the USB CDC port, so the current handle
  /// is dead: every later command would be written into nothing and the UI
  /// would keep showing stale data. Wait for the port to come back and reopen
  /// it, so the user does not have to reconnect by hand.
  void _scheduleReconnect(
      {Duration delay = const Duration(seconds: 4)}) {
    final port = _selectedPort;
    if (port == null) return;
    _reconnectTimer?.cancel();
    _isReconnecting = true;
    notifyListeners();
    _reconnectTimer = Timer(delay, () => _reconnect(port));
  }

  Future<void> _reconnect(String port) async {
    stopLogStream();
    _statusTimer?.cancel();
    _statusTimer = null;
    try {
      await _serial.disconnect();
    } catch (_) {}
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!SerialService.listPorts().contains(port)) continue;
      if (await connect(port)) {
        _isReconnecting = false;
        await refreshPorts();
        notifyListeners();
        return;
      }
    }
    _isReconnecting = false;
    notifyListeners();
  }

  void fetchLogs() {
    if (!_serial.isConnected) return;
    _serial.requestLogs();
  }

  /// Re-read device info (firmware, credential flags) without reconnecting.
  void refreshInfo() {
    if (!_serial.isConnected) return;
    _serial.requestInfo();
    _serial.requestStatus();
  }

  void _onResponse(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'info':
        _info = data;
        notifyListeners();
        // The device type (C3/C6/S3) is only known now, so re-check the
        // manifest against the right published artifact.
        checkManifest();
        break;
      case 'status':
        _status = data;
        notifyListeners();
        break;
      case 'logs':
        final raw = data['data'];
        if (raw is List) {
          _logs = raw
              .whereType<Map<String, dynamic>>()
              .map((e) => LogEntry.fromJson(e))
              .toList();
          _error = null;
          notifyListeners();
        }
        break;
      case 'ack':
        _error = null;
        notifyListeners();
        break;
      case 'error':
        _error = data['error'] as String? ?? 'Ошибка устройства';
        notifyListeners();
        break;
    }
  }

  /// Fetches the real published firmware version from the OTA site
  /// and compares it with the connected device's reported firmware.
  Future<void> checkManifest() async {
    if (_isCheckingManifest) {
      _manifestCheckQueued = true;
      return;
    }
    _isCheckingManifest = true;
    _manifestError = null;
    notifyListeners();

    final api = _otaApi;
    if (api == null) {
      _isCheckingManifest = false;
      notifyListeners();
      return;
    }
    try {
      final deviceType = _info?['device_type'] as String?;
      _manifest = await api.fetchManifest(deviceType: deviceType);
      if (_manifest == null) {
        _manifestError = 'Не удалось получить актуальную версию с сайта';
      }
    } catch (e) {
      _manifestError = e.toString();
    } finally {
      _isCheckingManifest = false;
      notifyListeners();
      if (_manifestCheckQueued) {
        _manifestCheckQueued = false;
        await checkManifest();
      }
    }
  }

  /// Ask the device to pull and apply the latest firmware via OTA.
  Future<String> sendOtaCommand() async {
    if (!isConnected) return 'Устройство не подключено';
    if (_isSendingOta) return 'Обновление уже запускается';

    _isSendingOta = true;
    notifyListeners();
    try {
      _serial.requestOta();
      // The board downloads the image, reboots into the new slot and
      // re-enumerates USB, so give it time and reopen the port afterwards.
      _scheduleReconnect(delay: const Duration(seconds: 30));
      // ack/error will come through _onResponse; simulate an immediate
      // informational result because the device may need a few seconds
      // to start downloading.
      return 'Команда ОТА отправлена — устройство скачает прошивку и перезагрузится';
    } finally {
      _isSendingOta = false;
      notifyListeners();
    }
  }

  /// Save new WiFi credentials; the device saves them to NVS and reboots.
  bool setWifi(String ssid, String password) {
    if (!_serial.isConnected) return false;
    _serial.setWifi(ssid, password);
    // The firmware reboots to apply the new credentials.
    _scheduleReconnect();
    return true;
  }

  void clearWifi() {
    _serial.clearWifi();
    _scheduleReconnect();
  }

  /// Stores the MQTT login (also used for the HTTP API) in the device NVS.
  bool setCredentials({
    required String user,
    required String password,
  }) {
    if (!_serial.isConnected) return false;
    _serial.setCredentials(user, password);
    return true;
  }

  bool get mqttUserSet => _info?['mqtt_user_set'] == true;
  bool get mqttPasswordSet => _info?['mqtt_pass_set'] == true;

  void restart() {
    _serial.restart();
    _scheduleReconnect(delay: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    stopLogStream();
    _statusTimer?.cancel();
    _reconnectTimer?.cancel();
    _respSub.cancel();
    _errorSub.cancel();
    _serial.dispose();
    super.dispose();
  }
}