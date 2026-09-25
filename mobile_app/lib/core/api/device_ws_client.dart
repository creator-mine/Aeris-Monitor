import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/device.dart';
import '../../models/log_entry.dart';

/// WebSocket channel to a single ESP32 device (ws://<ip>:81/ws).
///
/// The device pushes:
///   {"type":"sensor_update","data":{"timestamp":...,"modules":{moduleId:{key:value}}}}
///   {"type":"status_update", ...}
///   {"type":"modules_update","modules":[...]}
/// and answers explicit requests (request_sensors, request_status, ...).
class DeviceWsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _wsUrl;
  bool _manuallyClosed = false;

  void Function(Map<String, dynamic> sensorData)? onSensorUpdate;
  void Function(Map<String, dynamic> status)? onStatusUpdate;
  void Function(List<dynamic> modules)? onModulesUpdate;
  void Function(List<LogEntry> logs)? onLogsUpdate;
  void Function()? onConnected;
  void Function()? onDisconnected;

  bool get isConnected => _channel != null;

  Future<void> connect(Device device) async {
    await disconnect();
    _wsUrl = device.wsUrl;
    _manuallyClosed = false;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    final url = _wsUrl;
    if (url == null || _manuallyClosed) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
      onConnected?.call();
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> message;
    if (raw is String) {
      message = jsonDecode(raw) as Map<String, dynamic>;
    } else if (raw is List<int>) {
      message = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } else {
      return;
    }

    final type = message['type'];
    switch (type) {
      case 'sensor_update':
        onSensorUpdate?.call(
          (message['data'] as Map<String, dynamic>?) ?? const {},
        );
        break;
      case 'status_update':
        onStatusUpdate?.call(message);
        break;
      case 'modules_update':
        onModulesUpdate?.call(
          (message['modules'] as List<dynamic>?) ?? const [],
        );
        break;
      case 'logs':
        onLogsUpdate?.call(
          ((message['data'] as List<dynamic>?) ?? const [])
              .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
        break;
      default:
        break;
    }
  }

  void requestSensors() {
    _send({'type': 'request_sensors'});
  }

  void requestStatus() {
    _send({'type': 'request_status'});
  }

  void requestLogs() {
    _send({'type': 'request_logs'});
  }

  void sendCommand(String command, [Map<String, dynamic>? extra]) {
    _send({
      'type': 'command',
      'command': command,
      ...?extra,
    });
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || _manuallyClosed) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    onDisconnected?.call();

    if (!_manuallyClosed && _wsUrl != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), _openSocket);
    }
  }

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}