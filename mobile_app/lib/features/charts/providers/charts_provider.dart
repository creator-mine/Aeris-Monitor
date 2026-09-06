import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import '../../../core/api/direct_device_client.dart';
import '../../../models/sensor_data.dart';
import '../../../models/device.dart';
import '../../../core/config/app_config.dart';

class ChartsProvider extends ChangeNotifier {
  DirectDeviceClient? _deviceClient;

  Map<String, SensorDataSeries> _dataSeries = {};
  String? _selectedDeviceId;
  String _selectedSensorType = '';
  DateTimeRange _timeRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(hours: 24)),
    end: DateTime.now(),
  );
  bool _isLoading = false;
  String? _error;
  List<MetricInfo> _deviceMetrics = [];

  Map<String, SensorDataSeries> get dataSeries => _dataSeries;
  String? get selectedDeviceId => _selectedDeviceId;
  String get selectedSensorType => _selectedSensorType;
  DateTimeRange get timeRange => _timeRange;
  bool get isLoading => _isLoading;
  String? get error => _error;

  SensorDataSeries? get currentSeries => _dataSeries[_selectedSensorType];

  void setSelectedDevice(String deviceId, {List<MetricInfo> metrics = const [], Device? device}) {
    _selectedDeviceId = deviceId;
    _deviceMetrics = metrics;
    _dataSeries.clear();

    _deviceClient?.dispose();
    _deviceClient = null;
    final baseUrl = device?.httpBaseUrl;
    if (baseUrl != null) {
      _deviceClient = DirectDeviceClient(baseUrl: baseUrl);
    }

    if (_deviceMetrics.isNotEmpty) {
      _selectedSensorType = _deviceMetrics.first.key;
    } else {
      _selectedSensorType = AppConfig.defaultSensorUnits.keys.first;
    }

    notifyListeners();
    loadData();
  }

  void setSelectedSensorType(String sensorType) {
    _selectedSensorType = sensorType;
    notifyListeners();
  }

  void setTimeRange(DateTimeRange timeRange) {
    _timeRange = timeRange;
    notifyListeners();
    loadData();
  }

  Future<void> loadData() async {
    final client = _deviceClient;
    if (_selectedDeviceId == null || _selectedSensorType.isEmpty || client == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final series = await client.getHistory(
        _selectedSensorType,
        unit: getSensorUnit(_selectedSensorType),
        since: _timeRange.start,
        limit: _calculateLimit(),
      );
      _dataSeries[_selectedSensorType] = series;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  int _calculateLimit() {
    final hours = _timeRange.end.difference(_timeRange.start).inHours;
    if (hours <= 1) return 60;
    if (hours <= 24) return 500;
    return 1000;
  }

  List<String> get availableSensorTypes {
    if (_deviceMetrics.isNotEmpty) {
      return _deviceMetrics.map((m) => m.key).toList();
    }
    return AppConfig.defaultSensorUnits.keys.toList();
  }

  String getSensorUnit(String sensorType) {
    for (final metric in _deviceMetrics) {
      if (metric.key == sensorType) return metric.unit;
    }
    return AppConfig.defaultSensorUnits[sensorType] ?? '';
  }

  String getSensorName(String sensorType) {
    for (final metric in _deviceMetrics) {
      if (metric.key == sensorType) return metric.name;
    }
    return AppConfig.defaultSensorNames[sensorType] ?? sensorType;
  }

  @override
  void dispose() {
    _deviceClient?.dispose();
    super.dispose();
  }
}