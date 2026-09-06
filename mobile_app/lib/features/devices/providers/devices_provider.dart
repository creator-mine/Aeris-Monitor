import 'package:flutter/foundation.dart';
import '../../../core/api/signaling_api.dart';
import '../../../models/device.dart';

class DevicesProvider extends ChangeNotifier {
  final SignalingApi _signalingApi;

  List<Device> _devices = [];
  bool _isLoading = false;
  String? _error;

  DevicesProvider({required SignalingApi signalingApi})
      : _signalingApi = signalingApi;

  List<Device> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

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
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    await loadDevices();
  }

  Future<bool> deleteDevice(String id) async {
    try {
      final removed = await _signalingApi.removeDevice(id);
      if (removed) {
        _devices.removeWhere((d) => d.id == id);
      }
      notifyListeners();
      return removed;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Device? getDeviceById(String id) {
    try {
      return _devices.firstWhere((d) => d.id == id);
    } catch (e) {
      return null;
    }
  }
}