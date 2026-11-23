import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:dio/dio.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/config/connection_mode.dart';
import '../../../models/sensor_data.dart';
import '../../../models/device.dart';
import '../../../core/config/app_config.dart';

class ChartsProvider extends ChangeNotifier {
  DirectDeviceClient? _deviceClient;
  Device? _selectedDevice;

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

  void setSelectedDevice(String deviceId,
      {List<MetricInfo> metrics = const [], Device? device}) {
    _selectedDeviceId = deviceId;
    _selectedDevice = device;
    _deviceMetrics = metrics;
    _dataSeries.clear();
    _loadSeq++; // invalidate any request still running for the old device
    _isLoading = false;
    _error = null;

    _deviceClient?.dispose();
    _deviceClient = null;
    final baseUrl = LanPolicy.enabled ? device?.httpBaseUrl : null;
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

  @visibleForTesting
  void setChartDataForTest(String sensorType, SensorDataSeries series) {
    _selectedSensorType = sensorType;
    _dataSeries[sensorType] = series;
    notifyListeners();
  }

  void setTimeRange(DateTimeRange timeRange) {
    _timeRange = timeRange;
    notifyListeners();
    loadData();
  }

  Future<void> loadData() async {
    final client = _deviceClient;
    if (_selectedDeviceId == null || _selectedSensorType.isEmpty) {
      return;
    }

    if (!LanPolicy.enabled) {
      _isLoading = false;
      _error = 'Режим «Только MQTT»: история с SD-карты недоступна. '
          'Включите LAN в настройках.';
      notifyListeners();
      return;
    }

    final selected = _selectedDevice;
    if (selected != null && !selected.isOnline) {
      _isLoading = false;
      _error =
          'Устройство «${selected.name}» офлайн. Включите его или выберите онлайн-устройство в списке.';
      notifyListeners();
      return;
    }

    if (!isMetricSupported(_selectedSensorType)) {
      // The module is not on this board: nothing to request from the SD card.
      _isLoading = false;
      _error = null;
      _dataSeries.remove(_selectedSensorType);
      notifyListeners();
      return;
    }

    if (client == null) {
      _isLoading = false;
      _error =
          'У устройства нет IP-адреса. Подключите его к той же сети Wi-Fi и обновите список.';
      notifyListeners();
      return;
    }

    final seq = ++_loadSeq;
    final sensorType = _selectedSensorType;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final series = await _fetchHistory(
        client,
        sensorType,
        since: _timeRange.start,
        limit: _calculateLimit(),
      );
      // A newer request (device/sensor/range change) may have started while
      // this one was in flight — discard the stale response.
      if (_disposed || seq != _loadSeq) return;
      _dataSeries[sensorType] = series;
    } on DioException catch (e) {
      if (_disposed || seq != _loadSeq) return;
      if (_isConnectionError(e)) {
        final address = selected?.httpBaseUrl ?? 'устройству';
        _error = 'Устройство не ответило на запрос истории ($address). '
            'Данные с SD-карты временно недоступны — повторите попытку.';
      } else {
        _error = e.message ?? e.toString();
      }
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

  static bool _isConnectionError(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.receiveTimeout;

  /// The ESP32 occasionally drops the first HTTP connection while it is busy
  /// with a previous SD scan. One quiet retry turns that into a successful
  /// chart instead of an immediate "connection error" screen.
  Future<SensorDataSeries> _fetchHistory(
    DirectDeviceClient client,
    String sensorType, {
    required DateTime since,
    required int limit,
  }) async {
    try {
      return await client.getHistory(
        sensorType,
        unit: getSensorUnit(sensorType),
        since: since,
        limit: limit,
      );
    } on DioException catch (e) {
      if (!_isConnectionError(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return client.getHistory(
        sensorType,
        unit: getSensorUnit(sensorType),
        since: since,
        limit: limit,
      );
    }
  }

  int _calculateLimit([DateTimeRange? range]) {
    final r = range ?? _timeRange;
    final hours = r.end.difference(r.start).inHours;
    if (hours <= 1) return 60;
    if (hours <= 24) return 500;
    return 1000;
  }

  /// Keys that exist as metrics but make no sense as a time series: the IAQ
  /// calibration level (0..3) belongs on the dashboard tile, not in a chart.
  static const Set<String> _nonChartKeys = {'iaq_accuracy'};

  List<String> get availableSensorTypes {
    final keys = <String>[];
    // Always offer the full known set so the screen explains what the board
    // does not have instead of silently hiding parameters from other devices.
    for (final key in AppConfig.defaultSensorUnits.keys) {
      if (_nonChartKeys.contains(key)) continue;
      keys.add(key);
    }
    for (final metric in _deviceMetrics) {
      if (_nonChartKeys.contains(metric.key)) continue;
      if (AppConfig.isMetricHidden(metric.key)) continue;
      if (!keys.contains(metric.key)) keys.add(metric.key);
    }
    return keys;
  }

  /// Whether the selected device actually has this metric. When the module
  /// list has not arrived yet the device is treated as capable so the history
  /// request can still be attempted instead of showing a false "not connected".
  bool isMetricSupported(String sensorType) {
    if (AppConfig.isMetricHidden(sensorType)) return false;
    if (_deviceMetrics.isEmpty) return true;
    return _deviceMetrics.any((metric) => metric.key == sensorType);
  }

  bool get isSelectedMetricSupported => isMetricSupported(_selectedSensorType);

  /// Loads the same sensor series from several devices for overlay
  /// comparison. Devices without a usable IP are skipped.
  Future<void> loadComparison(
    List<Device> devices,
    String sensorType, {
    required DateTimeRange range,
  }) async {
    final candidates = devices.where((d) => d.httpBaseUrl != null).toList();
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
    // The module reports English names (for example "Illuminance"); prefer the
    // shared localized label for metrics the app knows about.
    final fallback = AppConfig.defaultSensorNames[sensorType];
    if (fallback != null) return fallback;
    for (final metric in _deviceMetrics) {
      if (metric.key == sensorType) return metric.name;
    }
    return sensorType;
  }

  @override
  void dispose() {
    _disposed = true;
    _deviceClient?.dispose();
    super.dispose();
  }
}
