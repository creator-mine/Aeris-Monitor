import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

/// FFI-backed serial port access (native platforms only).
///
/// Every libserialport call runs in a dedicated worker isolate. Opening a USB
/// CDC port can block for seconds while the device re-enumerates, and writes
/// can block on the driver's output buffer — doing that on the UI isolate
/// freezes the whole window (this is what "Подключиться" used to do).
///
/// The bundled `SerialPortReader` is deliberately not used: on Windows its
/// read loop spins at 100% of a core as soon as data arrives
/// (jpnurmi/flutter_libserialport#24), which also made the app unresponsive.
/// Instead the worker polls `bytesAvailable` from a short periodic timer and
/// drains the buffer with non-blocking reads.
class SerialIo {
  Isolate? _worker;
  SendPort? _commands;
  ReceivePort? _messages;

  final StreamController<Uint8List> _data =
      StreamController<Uint8List>.broadcast();

  Completer<bool>? _opening;
  Completer<void>? _closing;
  bool _workerClosed = false;

  String? _lastError;
  bool _connected = false;
  String? _portName;

  /// Raw data received from the open port.
  Stream<Uint8List> get data => _data.stream;

  /// OS-provided message for the last failed operation.
  String? get lastError => _lastError;

  bool get isConnected => _connected;
  String? get portName => _portName;

  static bool get _unsupportedMobile => Platform.isAndroid || Platform.isIOS;

  static List<String> listPorts() =>
      _unsupportedMobile ? const [] : SerialPort.availablePorts;

  /// Opens `name` for reading and writing and configures 8N1 at `baudRate`.
  ///
  /// Completes with `false` instead of throwing; details land in [lastError].
  Future<bool> connect(String name, int baudRate) async {
    if (_unsupportedMobile) {
      _lastError = 'USB serial is not supported on this platform';
      return false;
    }
    await disconnect();

    _lastError = null;
    _portName = name;
    _workerClosed = false;

    final messages = ReceivePort()..listen(_onMessage);
    _messages = messages;

    final opening = Completer<bool>();
    _opening = opening;

    try {
      _worker = await Isolate.spawn(
        _serialWorker,
        _OpenRequest(messages.sendPort, name, baudRate),
        debugName: 'serial:$name',
        onError: messages.sendPort,
      );
    } catch (e) {
      _lastError = 'Не удалось запустить поток последовательного порта: $e';
      _reset();
      return false;
    }

    final ok = await opening.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _lastError = 'Порт $name не ответил (таймаут открытия)';
        return false;
      },
    );
    _opening = null;

    if (!ok) {
      await disconnect();
      return false;
    }
    return true;
  }

  /// Queues bytes for transmission. Never blocks: the worker isolate writes.
  void sendBytes(Uint8List bytes) {
    _commands?.send(_WriteRequest(bytes));
  }

  Future<void> disconnect() async {
    final worker = _worker;
    _connected = false;
    if (worker == null) {
      _reset();
      return;
    }

    if (!_workerClosed) {
      final closed = Completer<void>();
      _closing = closed;
      _commands?.send(const _CloseRequest());
      await closed.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
      _closing = null;
    }

    worker.kill(priority: Isolate.immediate);
    _reset();
  }

  Future<void> dispose() async {
    await disconnect();
    if (!_data.isClosed) await _data.close();
  }

  void _reset() {
    _worker = null;
    _commands = null;
    _messages?.close();
    _messages = null;
    _connected = false;
    _portName = null;
    _workerClosed = true;
  }

  void _onMessage(Object? raw) {
    if (raw is _ReadyReply) {
      _commands = raw.commands;
      return;
    }
    if (raw is _OpenReply) {
      _connected = raw.ok;
      if (!raw.ok) _lastError = raw.error;
      final opening = _opening;
      if (opening != null && !opening.isCompleted) opening.complete(raw.ok);
      return;
    }
    if (raw is _DataReply) {
      if (!_data.isClosed) _data.add(raw.bytes);
      return;
    }
    if (raw is _ErrorReply) {
      _lastError = raw.error;
      _connected = false;
      if (!_data.isClosed) _data.addError(raw.error);
      return;
    }
    if (raw is _ClosedReply) {
      _connected = false;
      _workerClosed = true;
      final closing = _closing;
      if (closing != null && !closing.isCompleted) closing.complete();
      return;
    }
    if (raw is List) {
      // Uncaught error / stack trace forwarded by `onError`.
      _lastError = raw.isEmpty ? 'Ошибка порта' : '${raw.first}';
      _connected = false;
      final opening = _opening;
      if (opening != null && !opening.isCompleted) opening.complete(false);
      final closing = _closing;
      if (closing != null && !closing.isCompleted) closing.complete();
    }
  }
}

// --- Messages exchanged with the worker isolate ---------------------------

class _OpenRequest {
  const _OpenRequest(this.reply, this.name, this.baudRate);
  final SendPort reply;
  final String name;
  final int baudRate;
}

class _ReadyReply {
  const _ReadyReply(this.commands);
  final SendPort commands;
}

class _OpenReply {
  const _OpenReply(this.ok, [this.error]);
  final bool ok;
  final String? error;
}

class _DataReply {
  const _DataReply(this.bytes);
  final Uint8List bytes;
}

class _ErrorReply {
  const _ErrorReply(this.error);
  final String error;
}

class _WriteRequest {
  const _WriteRequest(this.bytes);
  final Uint8List bytes;
}

class _CloseRequest {
  const _CloseRequest();
}

class _ClosedReply {
  const _ClosedReply();
}

// --- Worker isolate ------------------------------------------------------

const int _pollIntervalMs = 15;

void _serialWorker(_OpenRequest request) {
  final commands = ReceivePort();
  request.reply.send(_ReadyReply(commands.sendPort));

  SerialPort? port;
  Timer? poll;
  var finished = false;

  void shutdown({String? error}) {
    if (finished) return;
    finished = true;
    poll?.cancel();
    poll = null;
    final current = port;
    port = null;
    if (current != null) {
      try {
        current.close();
      } catch (_) {}
      try {
        current.dispose();
      } catch (_) {}
    }
    commands.close();
    if (error != null) request.reply.send(_ErrorReply(error));
    request.reply.send(const _ClosedReply());
  }

  void drain() {
    final current = port;
    if (current == null) return;
    try {
      var available = current.bytesAvailable;
      while (available > 0) {
        final chunk = current.read(available);
        if (chunk.isEmpty) break;
        request.reply.send(_DataReply(chunk));
        available = current.bytesAvailable;
      }
    } catch (e) {
      shutdown(error: '$e');
    }
  }

  commands.listen((dynamic message) {
    if (message is _WriteRequest) {
      final current = port;
      if (current == null) return;
      try {
        current.write(message.bytes, timeout: 500);
      } catch (e) {
        shutdown(error: '$e');
      }
      return;
    }
    if (message is _CloseRequest) {
      shutdown();
    }
  });

  try {
    final opened = SerialPort(request.name);
    if (!opened.openReadWrite()) {
      final message = '${SerialPort.lastError}';
      opened.dispose();
      request.reply.send(_OpenReply(false, message));
      return;
    }

    final config = opened.config;
    config.baudRate = request.baudRate;
    config.bits = 8;
    config.parity = SerialPortParity.none;
    config.stopBits = 1;
    config.setFlowControl(SerialPortFlowControl.none);
    opened.config = config;

    // Drop whatever the board printed while the port was opening.
    opened.flush(SerialPortBuffer.input);

    port = opened;
    request.reply.send(const _OpenReply(true));
    poll = Timer.periodic(
      const Duration(milliseconds: _pollIntervalMs),
      (_) => drain(),
    );
  } catch (e) {
    request.reply.send(_OpenReply(false, '$e'));
    shutdown();
  }
}
