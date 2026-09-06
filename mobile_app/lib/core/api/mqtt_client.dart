import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';
import '../../models/sensor_data.dart';

class MqttService {
  MqttServerClient? _client;
  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  bool _isConnected = false;
  String? _currentDeviceId;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _updatesSub;

  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<String> get statusStream => _statusController.stream;
  bool get isConnected => _isConnected;

  Future<bool> connect({
    String? broker,
    int? port,
    String? clientId,
    bool useWebSocket = false,
    bool fallbackToTcp = true,
    String? username,
    String? password,
  }) async {
    var ok = await _tryConnect(useWebSocket, broker, port, clientId, username, password);
    if (!ok && useWebSocket && fallbackToTcp) {
      _statusController.add('ws_failed_fallback_tcp');
      ok = await _tryConnect(false, broker, 1883, clientId, username, password);
    }
    return ok;
  }

  /// Drops the current connection and reconnects with new broker
  /// parameters, keeping the active device subscription.
  Future<bool> reconnect({
    String? broker,
    int? port,
    bool useWebSocket = false,
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
      fallbackToTcp: false,
      username: username,
      password: password,
    );
  }

  Future<bool> _tryConnect(bool linkWebSocket, String? broker, int? port, String? clientId,
      String? username, String? password) async {
    try {
      final b = broker ?? AppConfig.mqttBroker;
      final p = port ?? AppConfig.mqttPort;
      final id = clientId ?? 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';

      _client = MqttServerClient.withPort(b, id, p);
      _client!.useWebSocket = linkWebSocket;

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

    _currentDeviceId = deviceId;
    final prefix = AppConfig.mqttTopicPrefix;
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

    final prefix = AppConfig.mqttTopicPrefix;
    _client!.unsubscribe('$prefix/$deviceId/sensors/#');
    _client!.unsubscribe('$prefix/$deviceId/status');
    _currentDeviceId = null;
  }

  void _handleMessage(String topic, String payload) {
    if (topic.endsWith('/status')) {
      _statusController.add(payload);
      return;
    }

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final sensorData = SensorData.fromJson(data);
      _sensorDataController.add(sensorData);
    } catch (e) {
      _statusController.add('parse_error: $e');
    }
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

    if (_currentDeviceId != null) {
      subscribeToDevice(_currentDeviceId!);
    }
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
