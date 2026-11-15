import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'serial_io.dart';

/// USB serial bridge to the ESP32 for local device setup.
///
/// Protocol (line-based, over 115200 8N1):
///   PC  → ESP32: CMD:command[:arg...]\n
///   ESP → PC:    >>{json}\n   (the >> prefix filters out normal debug output)
class SerialService {
  static const int baudRate = 115200;

  final SerialIo _io = SerialIo();
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();

  StreamSubscription<Uint8List>? _ioSub;
  String _lineBuffer = '';

  /// Stream of parsed responses (each a JSON object with a "type" field).
  Stream<Map<String, dynamic>> get responses => _responses.stream;

  /// Stream of human-readable errors.
  Stream<String> get errors => _errors.stream;

  bool get isConnected => _io.isConnected;
  String? get portName => _io.portName;

  static List<String> listPorts() => SerialIo.listPorts();

  Future<bool> connect(String name) async {
    await disconnect();

    if (!await _io.connect(name, baudRate)) {
      _errors.add(_io.lastError ?? 'Не удалось открыть порт $name');
      return false;
    }

    _lineBuffer = '';

    await _ioSub?.cancel();
    _ioSub = _io.data.listen(
      _onData,
      onError: (Object e) => _errors.add('$e'),
    );
    return true;
  }

  Future<void> disconnect() async {
    await _ioSub?.cancel();
    _ioSub = null;
    await _io.disconnect();
    _lineBuffer = '';
  }

  void _onData(Uint8List data) {
    _lineBuffer += utf8.decode(data, allowMalformed: true);
    while (true) {
      final newline = _lineBuffer.indexOf('\n');
      if (newline < 0) break;
      final line = _lineBuffer.substring(0, newline).trim();
      _lineBuffer = _lineBuffer.substring(newline + 1);
      _processLine(line);
    }
  }

  void _processLine(String line) {
    if (!line.startsWith('>>')) return;
    final jsonStr = line.substring(2).trim();
    if (jsonStr.isEmpty) return;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        _responses.add(decoded);
      }
    } catch (_) {
      // ignore malformed JSON from a debug line
    }
  }

  void _send(String command) {
    _io.sendBytes(utf8.encode('CMD:$command\n'));
  }

  void requestStatus() => _send('status');
  void requestLogs() => _send('logs');
  void requestSensors() => _send('sensors');
  void requestModules() => _send('modules');
  void requestInfo() => _send('info');

  void setWifi(String ssid, String password) {
    _send('wifi_set:$ssid:$password');
  }

  void clearWifi() => _send('wifi_clear');
  void restart() => _send('restart');

  /// Stores MQTT + API credentials in the device NVS.
  ///
  /// Empty fields keep whatever is already stored on the device. The device
  /// applies them on the next MQTT reconnect, no reboot is required.
  void setCredentials(String user, String password, String token) {
    final payload = jsonEncode({
      'user': user,
      'password': password,
      'token': token,
    });
    _send('secrets_set:$payload');
  }

  /// Ask the device to pull and apply the latest published firmware via OTA.
  void requestOta({bool force = false}) {
    _send(force ? 'ota:force' : 'ota');
  }

  void dispose() {
    _ioSub?.cancel();
    _ioSub = null;
    unawaited(_io.dispose());
    _responses.close();
    _errors.close();
  }
}