import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

/// FFI-backed serial port access (native platforms only).
class SerialIo {
  SerialPort? _port;
  StreamSubscription<Uint8List>? _readerSub;
  final StreamController<Uint8List> _data =
      StreamController<Uint8List>();
  String? _lastError;

  /// Raw data received from the open port.
  Stream<Uint8List> get data => _data.stream;

  /// OS-provided message for the last failed operation.
  String? get lastError => _lastError;

  bool get isConnected => _port?.isOpen ?? false;
  String? get portName => _port?.name;

  static List<String> listPorts() => SerialPort.availablePorts;

  /// Opens `name` for reading and writing and configures 8N1 at `baudRate`.
  bool connect(String name, int baudRate) {
    disconnect();

    try {
      final port = SerialPort(name);
      if (!port.openReadWrite()) {
        _lastError = '${SerialPort.lastError}';
        port.dispose();
        return false;
      }

      port.flush(SerialPortBuffer.both);

      final config = port.config;
      config.baudRate = baudRate;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      port.config = config;

      _port = port;
      _readerSub = SerialPortReader(port).stream.listen(
            _data.add,
            onError: (Object e) => _data.addError(e),
          );
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  void sendBytes(Uint8List bytes) {
    final port = _port;
    if (port == null || !port.isOpen) return;
    port.write(bytes);
    port.drain();
  }

  void disconnect() {
    _readerSub?.cancel();
    _readerSub = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }

  void dispose() {
    disconnect();
    _data.close();
  }
}