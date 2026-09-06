import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/api/signaling_api.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/api/device_ws_client.dart';
import '../../../core/api/mqtt_client.dart';
import '../../../models/device.dart';
import '../../../models/sensor_data.dart';

class DashboardProvider extends ChangeNotifier {
  final SignalingApi _signalingApi;
  final DeviceWsClient _wsClient;
  final MqttService? _mqtt;
  StreamSubscription<SensorData>? _mqttSensorSub;
  DirectDeviceClient? _deviceClient;

  List<Device> _devices = [];
  Device? _selectedDevice;
  Map<String, SensorData> _latestSensorData = {};
  bool _isLoading = false;
  String? _error;
  bool _isConnected = false;
  DateTime? _lastUpdate;

  DashboardProvider({required SignalingApi signalingApi, MqttService? mqtt})
      : _signalingApi = signalingApi,
        _mqtt = mqtt,
        _wsClient = DeviceWsClient() {
    _wsClient
      ..onSensorUpdate = _handleSensorUpdate
      ..onModulesUpdate = _handleModulesUpdate
      ..onStatusUpdate = _handleStatusUpdate
      ..onConnected = _handleConnected
      ..onDisconnected = _handleDisconnected;

    _mqttSensorSub = mqtt?.sensorDataStream.listen(updateSensorData);
  }

  List<Device> get devices => _devices;
  Device? get selectedDevice => _selectedDevice;
  Map<String, SensorData> get latestSensorData => _latestSensorData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;
  DateTime? get lastUpdate => _lastUpdate;

  List<Device> get onlineDevices =>
      _devices.where((d) => d.isOnline).toList();

  List<Device> get offlineDevices =>
      _devices.where((d) => !d.isOnline).toList();

  Future<void> loadDevices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _devices = await _signalingApi.getDevices();
      if (_devices.isNotEmpty && _selectedDevice == null) {
        selectDevice(_devices.first);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectDevice(Device device) async {
    await _wsClient.disconnect();
    _deviceClient?.dispose();
    _deviceClient = null;

    _mqtt?.unsubscribeFromDevice(_selectedDevice?.id ?? '');

    _selectedDevice = device;
    _latestSensorData.clear();
    _lastUpdate = null;
    _isConnected = false;

    final baseUrl = device.httpBaseUrl;
    if (baseUrl != null) {
      notifyListeners();
      _deviceClient = DirectDeviceClient(baseUrl: baseUrl);
      await _wsClient.connect(device);
    } else {
      notifyListeners();
    }

    _mqtt?.subscribeToDevice(device.id);
  }

  void _handleSensorUpdate(Map<String, dynamic> data) {
    final modules = data['modules'];
    if (modules is! Map) return;

    final now = DateTime.now();
    modules.forEach((moduleId, metrics) {
      if (metrics is! Map) return;
      metrics.forEach((key, value) {
        if (value is num) {
          _latestSensorData[key.toString()] = SensorData(
            deviceId: _selectedDevice?.id ?? '',
            sensorType: key.toString(),
            timestamp: now,
            data: {key.toString(): value.toDouble()},
          );
        }
      });
    });

    _lastUpdate = now;
    notifyListeners();
  }

  void _handleModulesUpdate(List<dynamic> modulesJson) {
    final modules = modulesJson
        .map((json) => Module.fromJson(json as Map<String, dynamic>))
        .toList();

    final device = _selectedDevice;
    if (device != null) {
      _selectedDevice = device.copyWith(modules: modules);
      notifyListeners();
    }
  }

  void _handleStatusUpdate(Map<String, dynamic> status) {
    notifyListeners();
  }

  void _handleConnected() {
    _isConnected = true;
    notifyListeners();
  }

  void _handleDisconnected() {
    _isConnected = false;
    notifyListeners();
  }

  void updateSensorData(SensorData data) {
    _latestSensorData[data.sensorType] = data;
    notifyListeners();
  }

  void sendCommand(String command) {
    final mqtt = _mqtt;
    final deviceId = _selectedDevice?.id;
    if (mqtt != null && mqtt.isConnected && deviceId != null) {
      mqtt.publishCommand(deviceId, {'type': 'command', 'command': command});
    } else {
      _wsClient.sendCommand(command);
    }
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
    _mqttSensorSub?.cancel();
    _mqtt?.unsubscribeFromDevice(_selectedDevice?.id ?? '');
    _wsClient.disconnect();
    _deviceClient?.dispose();
    super.dispose();
  }
}