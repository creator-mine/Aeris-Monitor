import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/api/signaling_api.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/api/device_ws_client.dart';
import '../../../core/api/mqtt_client.dart';
import '../../../core/api/lan_discovery.dart';
import '../../../core/api/lan_devices.dart';
import '../../../core/config/connection_mode.dart';
import '../../../models/device.dart';
import '../../../models/sensor_data.dart';
import '../../../core/parsers/sensor_frame_parser.dart';

class DashboardProvider extends ChangeNotifier {
  final SignalingApi _signalingApi;
  final DeviceWsClient _wsClient;
  final MqttService? _mqtt;
  StreamSubscription<SensorData>? _mqttSensorSub;
  StreamSubscription<bool>? _mqttConnSub;
  DirectDeviceClient? _deviceClient;

  ConnectionMode _mode;
  ActiveChannel _activeChannel = ActiveChannel.none;
  bool _disposed = false;
  int _connectionSeq = 0;

  /// Optional sink for LAN-direct sensor readings (used by the smart-home
  /// rule engine). Set from main() after both providers exist.
  void Function(SensorData data)? onSensorReading;

  List<Device> _devices = [];
  Device? _selectedDevice;
  final Map<String, SensorData> _latestSensorData = {};
  bool _isLoading = false;
  String? _error;
  bool _isConnected = false;
  bool _mqttConnected = false;
  DateTime? _lastUpdate;

  DashboardProvider({
    required SignalingApi signalingApi,
    MqttService? mqtt,
    ConnectionMode mode = ConnectionMode.auto,
  })  : _signalingApi = signalingApi,
        _mqtt = mqtt,
        _mode = mode,
        _wsClient = DeviceWsClient() {
    _wsClient
      ..onSensorUpdate = _handleSensorUpdate
      ..onModulesUpdate = _handleModulesUpdate
      ..onStatusUpdate = _handleStatusUpdate
      ..onConnected = _handleConnected
      ..onDisconnected = _handleDisconnected;

    _mqttSensorSub = mqtt?.sensorDataStream.listen(updateSensorData);
    _mqttConnected = mqtt?.isConnected ?? false;
    _mqttConnSub = mqtt?.connectionStream.listen(_onMqttConnectionChanged);
  }

  List<Device> get devices => _devices;
  Device? get selectedDevice => _selectedDevice;
  Map<String, SensorData> get latestSensorData => _latestSensorData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;
  bool get isMqttConnected => _mqttConnected;
  DateTime? get lastUpdate => _lastUpdate;
  ConnectionMode get connectionMode => _mode;
  ActiveChannel get activeChannel => _activeChannel;

  String? get activeChannelLabel {
    switch (_activeChannel) {
      case ActiveChannel.lan:
        return 'LAN';
      case ActiveChannel.mqtt:
        return 'MQTT';
      case ActiveChannel.none:
        return null;
    }
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
      if (_devices.isNotEmpty) _error = null;
      if (_disposed) return;
      final previousId = _selectedDevice?.id;
      if (previousId != null) {
        // Keep the selection in sync with fresh status/firmware/IP without
        // tearing down the active connection.
        for (final device in _devices) {
          if (device.id == previousId) {
            _selectedDevice = device;
            break;
          }
        }
      }
      if (_devices.isNotEmpty && _selectedDevice == null) {
        await selectDevice(_devices.first);
      }
    } catch (e) {
      // Cloud registry is optional: discover the device on the local network.
      final lan = await discoverLanDevices();
      _devices = mergeLanDevices(const [], lan);
      _error = _devices.isEmpty ? e.toString() : null;
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> selectDevice(Device device) async {
    final seq = ++_connectionSeq;
    _selectedDevice = device;
    _latestSensorData.clear();
    _lastUpdate = null;
    _isConnected = false;
    _safeNotify();
    await _applyConnection(device, seq);
  }

  /// Switches the data channel and re-applies the connection for the
  /// currently selected device.
  Future<void> setConnectionMode(ConnectionMode mode) async {
    if (mode == _mode) return;
    final seq = ++_connectionSeq;
    _mode = mode;
    _activeChannel = ActiveChannel.none;
    _safeNotify();
    final device = _selectedDevice;
    if (device != null) {
      await _applyConnection(device, seq);
    }
  }

  Future<void> _applyConnection(Device device, int seq) async {
    await _wsClient.disconnect();
    _deviceClient?.dispose();
    _deviceClient = null;

    _mqtt?.unsubscribeFromDevice(device.id);
    _isConnected = false;

    final wantsDirect = _mode != ConnectionMode.mqtt;
    if (wantsDirect) {
      var target = device;
      if (target.httpBaseUrl == null) {
        // No IP from the registry (or the registry is down): look for the
        // device on the local network before giving up on the direct channel.
        final lan = await discoverLanDevices(
          timeout: const Duration(milliseconds: 1200),
        );
        if (seq != _connectionSeq || _disposed) return;
        for (final candidate in lan) {
          if (candidate.id == device.id) {
            target = applyLanDiscovery(device, candidate);
            break;
          }
        }
        if (!identical(target, device)) {
          _selectedDevice = target;
          final index = _devices.indexWhere((d) => d.id == target.id);
          if (index >= 0) _devices[index] = target;
        }
      }
      final baseUrl = target.httpBaseUrl;
      if (baseUrl != null) {
        _deviceClient = DirectDeviceClient(baseUrl: baseUrl);
        await _wsClient.connect(target);
        if (seq != _connectionSeq || _disposed) return;
      }
    }

    final wantsMqtt = _mode != ConnectionMode.lanDirect;
    if (wantsMqtt) {
      _mqtt?.subscribeToDevice(device.id);
    }

    if (seq != _connectionSeq || _disposed) return;
    _updateActiveChannel();
    _safeNotify();
  }

  void _updateActiveChannel() {
    switch (_mode) {
      case ConnectionMode.lanDirect:
        _activeChannel = _isConnected ? ActiveChannel.lan : ActiveChannel.none;
        break;
      case ConnectionMode.mqtt:
        _activeChannel =
            _mqttConnected ? ActiveChannel.mqtt : ActiveChannel.none;
        break;
      case ConnectionMode.auto:
        _activeChannel = _isConnected
            ? ActiveChannel.lan
            : (_mqttConnected ? ActiveChannel.mqtt : ActiveChannel.none);
        break;
    }
  }

  void _onMqttConnectionChanged(bool connected) {
    if (_disposed) return;
    _mqttConnected = connected;
    _updateActiveChannel();
    _safeNotify();
  }

  void _handleSensorUpdate(Map<String, dynamic> data) {
    if (_disposed) return;
    final now = DateTime.now();
    final parsed = SensorFrameParser.parse(
      data,
      now,
      deviceId: _selectedDevice?.id ?? '',
    );
    if (parsed.isEmpty) return;

    _latestSensorData.addAll(parsed);
    _lastUpdate = now;
    for (final reading in parsed.values) {
      onSensorReading?.call(reading);
    }
    _safeNotify();
  }

  void _handleModulesUpdate(List<dynamic> modulesJson) {
    if (_disposed) return;
    final modules = modulesJson
        .map((json) => Module.fromJson(json as Map<String, dynamic>))
        .toList();

    final device = _selectedDevice;
    if (device != null) {
      _selectedDevice = device.copyWith(modules: modules);
      _safeNotify();
    }
  }

  void _handleStatusUpdate(Map<String, dynamic> status) {
    _safeNotify();
  }

  void _handleConnected() {
    if (_disposed) return;
    _isConnected = true;
    _updateActiveChannel();
    _safeNotify();
  }

  void _handleDisconnected() {
    if (_disposed) return;
    _isConnected = false;
    _updateActiveChannel();
    _safeNotify();
  }

  void updateSensorData(SensorData data) {
    if (_disposed) return;

    // Smart-home rules subscribe to every device (`iot/+/sensors/#`), so the
    // dashboard must ignore readings that belong to another device.
    final selectedId = _selectedDevice?.id;
    if (selectedId != null &&
        data.deviceId.isNotEmpty &&
        data.deviceId != selectedId) {
      return;
    }

    _latestSensorData[data.sensorType] = data;
    _lastUpdate = DateTime.now();
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Returns false when neither channel can deliver the command.
  bool sendCommand(String command) {
    final mqtt = _mqtt;
    final deviceId = _selectedDevice?.id;
    final useMqtt = _mode == ConnectionMode.mqtt ||
        (_mode == ConnectionMode.auto && !_isConnected);
    if (mqtt != null && useMqtt && deviceId != null && _mqttConnected) {
      mqtt.publishCommand(deviceId, {'type': 'command', 'command': command});
      return true;
    }
    if (_isConnected) {
      _wsClient.sendCommand(command);
      return true;
    }
    return false;
  }

  Future<void> refreshData() async {
    await loadDevices();
  }

  bool hasSensorData(String sensorType) {
    return _latestSensorData.containsKey(sensorType);
  }

  SensorData? getSensorData(String sensorType) {
    return _latestSensorData[sensorType];
  }

  double? getSensorValue(String sensorType) {
    final data = _latestSensorData[sensorType];
    if (data == null) return null;
    return data.getValue(sensorType);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionSeq++;
    _mqttSensorSub?.cancel();
    _mqttSensorSub = null;
    _mqttConnSub?.cancel();
    _mqttConnSub = null;
    _mqtt?.unsubscribeFromDevice(_selectedDevice?.id ?? '');
    _wsClient
      ..onSensorUpdate = null
      ..onModulesUpdate = null
      ..onStatusUpdate = null
      ..onConnected = null
      ..onDisconnected = null
      ..disconnect();
    _deviceClient?.dispose();
    super.dispose();
  }
}