import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';
import '../../models/sensor_data.dart';
import '../parsers/sensor_frame_parser.dart';

class MqttService {
  MqttServerClient? _client;
  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  bool _isConnected = false;
  String? _currentDeviceId;
  bool _subscribeAll = false;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _updatesSub;

  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<String> get statusStream => _statusController.stream;
  bool get isConnected => _isConnected;

  Future<bool> connect({
    String? broker,
    int? port,
    String? clientId,
    bool useWebSocket = false,
    bool secure = false,
    bool fallbackToTcp = true,
    String? username,
    String? password,
  }) async {
    var ok = await _tryConnect(
        useWebSocket, broker, port, clientId, username, password, secure);
    if (!ok && useWebSocket && fallbackToTcp) {
      _statusController.add('ws_failed_fallback_tls');
      ok = await _tryConnect(false, broker, 8883, clientId, username, password, true);
    }
    return ok;
  }

  /// Drops the current connection and reconnects with new broker
  /// parameters, keeping the active device subscription.
  Future<bool> reconnect({
    String? broker,
    int? port,
    bool useWebSocket = false,
    bool secure = false,
    String? username,
    String? password,
  }) async {
    _updatesSub?.cancel();
    _client?.disconnect();
    _isConnected = false;
    return connect(
      broker: broker,
      port: port,
      useWebSocket: useWebSocket,
      secure: secure,
      fallbackToTcp: false,
      username: username,
      password: password,
    );
  }

  Future<bool> _tryConnect(bool linkWebSocket, String? broker, int? port, String? clientId,
      String? username, String? password, bool secure) async {
    try {
      final b = broker ?? AppConfig.mqttBroker;
      final p = port ?? AppConfig.mqttPort;
      final id = clientId ?? 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';

      _client = MqttServerClient.withPort(b, id, p);
      _client!.useWebSocket = linkWebSocket;
      _client!.secure = secure;

      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.resubscribeOnAutoReconnect = true;

      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId ?? 'flutter_app')
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      final user = username ?? AppConfig.mqttUsername;
      final pass = password ?? AppConfig.mqttPassword;
      connMessage.authenticateAs(user, pass);

      _client!.connectionMessage = connMessage;

      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        _isConnected = true;
        _statusController.add('connected');
        return true;
      } else {
        _isConnected = false;
        _statusController.add('disconnected');
        return false;
      }
    } catch (e) {
      _isConnected = false;
      _statusController.add('error: $e');
      _client?.disconnect();
      return false;
    }
  }

  void disconnect() {
    _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _isConnected = false;
    _statusController.add('disconnected');
  }

  void subscribeToDevice(String deviceId) {
    if (!_isConnected || _client == null) return;

    final previous = _currentDeviceId;
    if (previous != null && previous != deviceId) {
      const prefix = AppConfig.mqttTopicPrefix;
      try {
        _client!.unsubscribe('$prefix/$previous/sensors/#');
        _client!.unsubscribe('$prefix/$previous/status');
      } catch (_) {}
    }

    _currentDeviceId = deviceId;
    const prefix = AppConfig.mqttTopicPrefix;
    _client!.subscribe('$prefix/$deviceId/sensors/#', MqttQos.atMostOnce);
    _client!.subscribe('$prefix/$deviceId/status', MqttQos.atMostOnce);

    _updatesSub?.cancel();
    final updates = _client!.updates;
    if (updates == null) return;

    _updatesSub = updates.listen((List<MqttReceivedMessage<MqttMessage?>> messages) {
      for (final message in messages) {
        final topic = message.topic;
        final payload = message.payload as MqttPublishMessage;
        final messageBytes = payload.payload.message;
        final payloadString = utf8.decode(messageBytes);

        _handleMessage(topic, payloadString);
      }
    });
  }

  void unsubscribeFromDevice(String deviceId) {
    if (!_isConnected || _client == null) return;

    const prefix = AppConfig.mqttTopicPrefix;
    _client!.unsubscribe('$prefix/$deviceId/sensors/#');
    _client!.unsubscribe('$prefix/$deviceId/status');
    _currentDeviceId = null;
  }

  /// Subscribes to sensor/status topics of ALL devices (`iot/+/sensors/#`,
  /// `iot/+/status`) so smart-home rules can evaluate any device's telemetry.
  /// Callers must keep the returned subscription alive.
  void subscribeAllDevices() {
    _subscribeAll = true;
    if (!_isConnected || _client == null) return;

    const prefix = AppConfig.mqttTopicPrefix;
    _client!.subscribe('$prefix/+/sensors/#', MqttQos.atMostOnce);
    _client!.subscribe('$prefix/+/status', MqttQos.atMostOnce);
  }

  void unsubscribeAllDevices() {
    _subscribeAll = false;
    if (!_isConnected || _client == null) return;

    const prefix = AppConfig.mqttTopicPrefix;
    _client!.unsubscribe('$prefix/+/sensors/#');
    _client!.unsubscribe('$prefix/+/status');
  }

  void _handleMessage(String topic, String payload) {
    final topicDeviceId = _topicDeviceId(topic);
    final isStatus = topic.endsWith('/status');

    if (isStatus) {
      _statusController.add(payload);
      return;
    }

    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final framed = SensorFrameParser.parse(
        json,
        DateTime.now(),
        deviceId: topicDeviceId,
      );
      if (framed.isNotEmpty) {
        framed.values.forEach(_sensorDataController.add);
        return;
      }

      final sensorData = SensorData.fromJson(json);
      _sensorDataController.add(SensorData(
        deviceId: topicDeviceId.isNotEmpty ? topicDeviceId : sensorData.deviceId,
        sensorType: _topicSensorType(topic) ?? sensorData.sensorType,
        timestamp: sensorData.timestamp,
        data: sensorData.data,
      ));
    } catch (e) {
      _statusController.add('parse_error: $e');
    }
  }

  /// Extracts the device id from `iot/<id>/sensors/...` or `iot/<id>/status`.
  String _topicDeviceId(String topic) {
    final parts = topic.split('/');
    return parts.length >= 3 ? parts[1] : '';
  }

  /// Extracts the sensor key from `iot/<id>/sensors/<name>` (empty otherwise).
  String? _topicSensorType(String topic) {
    final parts = topic.split('/');
    if (parts.length >= 4 && parts[2] == 'sensors') return parts[3];
    return null;
  }

  void publishCommand(String deviceId, Map<String, dynamic> command) {
    if (!_isConnected || _client == null) return;

    final topic = '${AppConfig.mqttTopicPrefix}/$deviceId/commands';
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(command));

    final payload = builder.payload;
    if (payload != null) {
      _client!.publishMessage(topic, MqttQos.atMostOnce, payload);
    }
  }

  void _onConnected() {
    _isConnected = true;
    _statusController.add('connected');

    if (_resubscribeAll()) return;
    if (_currentDeviceId != null) {
      subscribeToDevice(_currentDeviceId!);
    }
  }

  bool _resubscribeAll() {
    if (_subscribeAll) subscribeAllDevices();
    return _subscribeAll;
  }

  void _onDisconnected() {
    _isConnected = false;
    _statusController.add('disconnected');
  }

  void _onAutoReconnect() {
    _statusController.add('reconnecting');
  }

  void _onAutoReconnected() {
    _isConnected = true;
    _statusController.add('connected');

    if (_resubscribeAll()) return;
    if (_currentDeviceId != null) {
      subscribeToDevice(_currentDeviceId!);
    }
  }

  void dispose() {
    _updatesSub?.cancel();
    _sensorDataController.close();
    _statusController.close();
    _client?.disconnect();
  }
}
