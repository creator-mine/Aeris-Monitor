import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../models/alert.dart';

class AlertsProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<Alert> _alerts = [];
  bool _isLoading = false;
  String? _error;
  bool _disposed = false;

  AlertsProvider({required ApiClient apiClient}) : _apiClient = apiClient;

  List<Alert> get alerts => _alerts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Alert> get activeAlerts =>
      _alerts.where((a) => a.isActive).toList();

  List<Alert> get triggeredAlerts =>
      _alerts.where((a) => a.triggeredAt != null).toList();

  Future<void> loadAlerts() async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      _alerts = await _apiClient.getAlerts();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<bool> createAlert({
    required String deviceId,
    required String sensorType,
    required AlertType type,
    required double threshold,
  }) async {
    try {
      final alert = await _apiClient.createAlert({
        'device_id': deviceId,
        'sensor_type': sensorType,
        'type': type.name,
        'threshold': threshold,
      });
      if (_disposed) return true;
      _alerts.add(alert);
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Future<bool> updateAlert(String id, Map<String, dynamic> data) async {
    try {
      final alert = await _apiClient.updateAlert(id, data);
      if (_disposed) return true;
      final index = _alerts.indexWhere((a) => a.id == id);
      if (index != -1) {
        _alerts[index] = alert;
        _safeNotify();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Future<bool> toggleAlert(String id) async {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index == -1) return false;
    return updateAlert(id, {'is_active': !_alerts[index].isActive});
  }

  Future<bool> deleteAlert(String id) async {
    try {
      await _apiClient.deleteAlert(id);
      if (_disposed) return true;
      _alerts.removeWhere((a) => a.id == id);
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
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
