import 'dart:async';
import 'dart:typed_data';

/// No-op serial port access for platforms without native serial support
/// (e.g. web). Keeps the app compilable and reports no ports.
class SerialIo {
  final StreamController<Uint8List> _data =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get data => _data.stream;
  String? get lastError => null;
  bool get isConnected => false;
  String? get portName => null;

  static List<String> listPorts() => const [];

  bool connect(String name, int baudRate) => false;

  void sendBytes(Uint8List bytes) {}

  void disconnect() {}

  void dispose() {
    _data.close();
  }
}