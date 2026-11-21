import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../models/device.dart';
import '../../../models/sensor_data.dart';
import '../../../models/smart_rule.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/mqtt_client.dart';
import '../../../core/api/signaling_api.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../core/config/connection_mode.dart';
import '../../alerts/services/alert_notifier.dart';

/// Smart-home rule engine.
///
/// Receives sensor telemetry for ALL devices (MQTT wildcard subscription,
/// plus LAN-direct readings forwarded from the dashboard for the currently
/// selected device) and fires matching rules client-side:
///   notify          -> desktop notification (throttled by rule cooldown)
///   mqtt_command    -> publish {type:'command', command:<payload>} on iot/<id>/commands
///   device_command  -> HTTP POST to the device's REST command endpoint
///
/// Online/offline and no-data rules are evaluated from the signaling
/// registry snapshot polled every 30s.
class SmartHomeProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final MqttService? _mqtt;
  final SignalingApi _signalingApi;

  static const Duration _pollInterval = Duration(seconds: 30);

  List<SmartRule> _rules = [];
  final Map<String, DateTime> _lastFired = {};
  Map<String, bool> _lastDeviceStatus = {};
  final Map<String, String> _deviceNames = {};
  final Map<String, String> _deviceBaseUrls = {};
  StreamSubscription<SensorData>? _sensorSub;
  Timer? _pollTimer;
  bool _isLoading = false;
  String? _error;
  bool _disposed = false;
  bool _started = false;

  SmartHomeProvider({
    required ApiClient apiClient,
    MqttService? mqtt,
    required SignalingApi signalingApi,
  })  : _apiClient = apiClient,
        _mqtt = mqtt,
        _signalingApi = signalingApi;

  List<SmartRule> get rules => _rules;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<SmartRule> get enabledRules => _rules.where((r) => r.enabled).toList();

  String deviceName(String deviceId) => _deviceNames[deviceId] ?? deviceId;

  /// Activates telemetry subscriptions and loads the rule set.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _sensorSub = _mqtt?.sensorDataStream.listen(evaluateSensorData);
    _mqtt?.subscribeAllDevices();
    loadRules();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _syncDeviceStatuses());
    _syncDeviceStatuses();
  }

  /// Wires LAN-direct sensor frames (dashboard) into rule evaluation.
  void onLanSensorData(SensorData data) {
    if (!_disposed) evaluateSensorData(data);
  }

  Future<void> loadRules() async {
    if (_disposed) return;
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      _rules = await _apiClient.getRules();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<bool> createRule(SmartRule rule) async {
    try {
      final created = await _apiClient.createRule(_rulePayload(rule));
      if (_disposed) return true;
      _rules.insert(0, created);
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Future<bool> updateRule(SmartRule rule) async {
    try {
      final updated = await _apiClient.updateRule(rule.id, _rulePayload(rule));
      if (_disposed) return true;
      final index = _rules.indexWhere((r) => r.id == rule.id);
      if (index != -1) _rules[index] = updated;
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Future<bool> toggleRule(SmartRule rule) async {
    return updateRule(rule.copyWith(enabled: !rule.enabled));
  }

  Future<bool> deleteRule(String id) async {
    try {
      await _apiClient.deleteRule(id);
      if (_disposed) return true;
      _rules.removeWhere((r) => r.id == id);
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      return false;
    }
  }

  Map<String, dynamic> _rulePayload(SmartRule rule) => {
        'name': rule.name,
        'enabled': rule.enabled,
        'device_id': rule.deviceId,
        'trigger': ruleTriggerWire(rule.trigger),
        if (rule.sensorType.isNotEmpty) 'sensor_type': rule.sensorType,
        if (rule.threshold != null) 'threshold': rule.threshold,
        'action': ruleActionWire(rule.action),
        if (rule.actionPayload.isNotEmpty) 'action_payload': rule.actionPayload,
        'cooldown_seconds': rule.cooldownSeconds,
      };

  /// Core evaluation: threshold rules for incoming sensor readings.
  void evaluateSensorData(SensorData data) {
    if (_disposed || data.deviceId.isEmpty) return;

    final value = data.getValue(data.sensorType) ?? _firstNumeric(data.data);
    if (value == null) return;

    for (final rule in _rules) {
      if (!rule.enabled) continue;
      if (rule.deviceId != data.deviceId) continue;
      if (rule.sensorType != data.sensorType) continue;

      final threshold = rule.threshold;
      if (threshold == null) continue;

      final hit = rule.trigger == RuleTrigger.thresholdAbove
          ? value > threshold
          : rule.trigger == RuleTrigger.thresholdBelow
              ? value < threshold
              : false;
      if (hit) _fire(rule, value);
    }
  }

  /// Re-evaluates online/offline/no-data triggers against the registry.
  Future<void> _syncDeviceStatuses() async {
    if (_disposed) return;
    List<Device> devices;
    try {
      devices = await _signalingApi.getDevices();
    } catch (_) {
      return;
    }
    if (_disposed) return;

    final statuses = <String, bool>{};
    for (final device in devices) {
      statuses[device.id] = device.isOnline;
      _deviceNames[device.id] = device.name;
      final base = device.httpBaseUrl;
      if (base != null) _deviceBaseUrls[device.id] = base;
    }

    for (final rule in _rules) {
      if (!rule.enabled) continue;
      final wasOnline = _lastDeviceStatus[rule.deviceId];
      final isOnline = statuses[rule.deviceId];
      if (wasOnline == null || isOnline == null) continue;
      if (wasOnline == isOnline) continue;

      final trigger = rule.trigger;
      final firesOnTransition = (trigger == RuleTrigger.online && isOnline) ||
          (trigger == RuleTrigger.offline && !isOnline) ||
          (trigger == RuleTrigger.noData && !isOnline);
      if (firesOnTransition) _fire(rule, null);
    }

    _lastDeviceStatus = statuses;
  }

  void _fire(SmartRule rule, double? value) {
    final now = DateTime.now();
    final last = _lastFired[rule.id];
    if (last != null &&
        now.difference(last) < Duration(seconds: rule.cooldownSeconds)) {
      return;
    }
    _lastFired[rule.id] = now;

    final device = deviceName(rule.deviceId);
    final reason = _humanReadable(rule, value);
    final title = 'Умный дом · ${rule.name.isEmpty ? 'Правило' : rule.name}';

    switch (rule.action) {
      case RuleAction.notify:
        AlertNotifier.notify(title, '$device: $reason');
      case RuleAction.mqttCommand:
        _mqtt?.publishCommand(rule.deviceId, {
          'type': 'command',
          'command': rule.actionPayload,
        });
      case RuleAction.deviceCommand:
        _sendDeviceCommand(rule);
    }
  }

  Future<void> _sendDeviceCommand(SmartRule rule) async {
    if (rule.actionPayload.isEmpty) return;
    if (!LanPolicy.enabled) {
      _mqtt?.publishCommand(rule.deviceId, {
        'type': 'command',
        'command': rule.actionPayload,
      });
      return;
    }
    final baseUrl = _deviceBaseUrls[rule.deviceId];
    if (baseUrl == null) return;
    final client = DirectDeviceClient(baseUrl: baseUrl);
    try {
      await client.sendCommand(rule.actionPayload);
    } catch (_) {
    } finally {
      client.dispose();
    }
  }

  String _humanReadable(SmartRule rule, double? value) {
    switch (rule.trigger) {
      case RuleTrigger.thresholdAbove:
        return '${rule.sensorType} > ${rule.threshold} (сейчас ${value?.toStringAsFixed(1) ?? '—'})';
      case RuleTrigger.thresholdBelow:
        return '${rule.sensorType} < ${rule.threshold} (сейчас ${value?.toStringAsFixed(1) ?? '—'})';
      case RuleTrigger.online:
        return 'устройство вернулось в сеть';
      case RuleTrigger.offline:
      case RuleTrigger.noData:
        return 'устройство пропало из сети';
    }
  }

  double? _firstNumeric(Map<String, dynamic> data) {
    for (final v in data.values) {
      if (v is num) return v.toDouble();
    }
    return null;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _sensorSub?.cancel();
    _sensorSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _mqtt?.unsubscribeAllDevices();
    super.dispose();
  }
}
