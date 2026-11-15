import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import '../../../core/api/direct_device_client.dart';
import '../../../models/sensor_data.dart';
import '../../../models/device.dart';
import '../../../core/config/app_config.dart';

class ChartsProvider extends ChangeNotifier {
  DirectDeviceClient? _deviceClient;

  final Map<String, SensorDataSeries> _dataSeries = {};
  String? _selectedDeviceId;
  String _selectedSensorType = '';
  DateTimeRange _timeRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(hours: 24)),
    end: DateTime.now(),
  );
  bool _isLoading = false;
  String? _error;
  List<MetricInfo> _deviceMetrics = [];
  int _loadSeq = 0;

  // Multi-device comparison state (deviceId -> series / name).
  Map<String, SensorDataSeries> _compareSeries = {};
  Map<String, String> _compareNames = {};
  bool _isLoadingComparison = false;
  String? _comparisonError;
  bool _disposed = false;

  Map<String, SensorDataSeries> get dataSeries => _dataSeries;
  String? get selectedDeviceId => _selectedDeviceId;
  String get selectedSensorType => _selectedSensorType;
  DateTimeRange get timeRange => _timeRange;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isComparing => _compareSeries.isNotEmpty;
  Map<String, SensorDataSeries> get compareSeries => _compareSeries;
  Map<String, String> get compareNames => _compareNames;
  bool get isLoadingComparison => _isLoadingComparison;
  String? get comparisonError => _comparisonError;

  SensorDataSeries? get currentSeries => _dataSeries[_selectedSensorType];

  void setSelectedDevice(String deviceId, {List<MetricInfo> metrics = const [], Device? device}) {
    _selectedDeviceId = deviceId;
    _deviceMetrics = metrics;
    _dataSeries.clear();
    _loadSeq++; // invalidate any request still running for the old device
    _isLoading = false;
    _error = null;

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
    if (sensorType == _selectedSensorType) return;
    _selectedSensorType = sensorType;
    notifyListeners();
    // Each sensor has its own history endpoint; fetch it on first selection.
    if (!_dataSeries.containsKey(sensorType)) {
      loadData();
    }
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

    final seq = ++_loadSeq;
    final sensorType = _selectedSensorType;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final series = await client.getHistory(
        sensorType,
        unit: getSensorUnit(sensorType),
        since: _timeRange.start,
        limit: _calculateLimit(),
      );
      // A newer request (device/sensor/range change) may have started while
      // this one was in flight — discard the stale response.
      if (_disposed || seq != _loadSeq) return;
      _dataSeries[sensorType] = series;
    } catch (e) {
      if (_disposed || seq != _loadSeq) return;
      _error = e.toString();
    } finally {
      if (!_disposed && seq == _loadSeq) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  int _calculateLimit([DateTimeRange? range]) {
    final r = range ?? _timeRange;
    final hours = r.end.difference(r.start).inHours;
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

  /// Loads the same sensor series from several devices for overlay
  /// comparison. Devices without a usable IP are skipped.
  Future<void> loadComparison(
    List<Device> devices,
    String sensorType, {
    required DateTimeRange range,
  }) async {
    final candidates = devices
        .where((d) => d.httpBaseUrl != null)
        .toList();
    if (sensorType.isEmpty || candidates.isEmpty) return;

    _isLoadingComparison = true;
    _comparisonError = null;
    notifyListeners();

    final results = <String, SensorDataSeries>{};
    final names = <String, String>{};
    final clients = <DirectDeviceClient>[];

    try {
      await Future.wait(candidates.map((device) async {
        final client = DirectDeviceClient(baseUrl: device.httpBaseUrl!);
        clients.add(client);
        try {
          final series = await client.getHistory(
            sensorType,
            unit: _unitFor(sensorType, device),
            since: range.start,
            limit: _calculateLimit(range),
          );
          if (series.points.isNotEmpty) {
            results[device.id] = series;
            names[device.id] = device.name;
          }
        } catch (_) {}
      }));
    } finally {
      for (final client in clients) {
        client.dispose();
      }
      if (!_disposed) {
        _compareSeries = results;
        _compareNames = names;
        _isLoadingComparison = false;
        notifyListeners();
      }
    }
  }

  void clearComparison() {
    if (_compareSeries.isEmpty) return;
    _compareSeries = {};
    _compareNames = {};
    _comparisonError = null;
    notifyListeners();
  }

  String _unitFor(String sensorType, Device device) {
    final metric = device.metricInfo(sensorType);
    if (metric != null) return metric.unit;
    return AppConfig.defaultSensorUnits[sensorType] ?? '';
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
    _disposed = true;
    _deviceClient?.dispose();
    super.dispose();
  }
}