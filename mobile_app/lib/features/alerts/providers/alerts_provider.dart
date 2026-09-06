import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../models/alert.dart';

class AlertsProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<Alert> _alerts = [];
  bool _isLoading = false;
  String? _error;

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
    notifyListeners();

    try {
      _alerts = await _apiClient.getAlerts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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
      _alerts.add(alert);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAlert(String id, Map<String, dynamic> data) async {
    try {
      final alert = await _apiClient.updateAlert(id, data);
      final index = _alerts.indexWhere((a) => a.id == id);
      if (index != -1) {
        _alerts[index] = alert;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleAlert(String id) async {
    final alert = _alerts.firstWhere((a) => a.id == id);
    return updateAlert(id, {'is_active': !alert.isActive});
  }

  Future<bool> deleteAlert(String id) async {
    try {
      await _apiClient.deleteAlert(id);
      _alerts.removeWhere((a) => a.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
