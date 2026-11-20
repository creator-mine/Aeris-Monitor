import 'dart:async';
import 'dart:convert';

import '../../models/wifi_profile.dart';
import 'api_client.dart';
import 'direct_device_client.dart';
import '../serial/serial_service.dart';

/// Transport used by the Wi-Fi manager UI. The same screen works over the
/// device HTTP API (LAN) and over USB serial.
abstract class WifiTransport {
  bool get canScan => true;
  bool get canAdd => true;
  bool get canEdit => true;
  bool get canAuto => true;

  Future<WifiStatus> getStatus();
  Future<List<WifiScanEntry>> scan();
  Future<void> add(String ssid, String password, int priority);
  Future<void> remove(int id);
  Future<void> connect(int id);
  Future<void> setPriority(int id, int priority);
  Future<void> setEnabled(int id, bool enabled);
  Future<void> reorder(List<int> ids);
  Future<void> setAuto();
}

class HttpWifiTransport implements WifiTransport {
  final DirectDeviceClient _client;

  HttpWifiTransport(this._client);

  @override
  bool get canScan => true;
  @override
  bool get canAdd => true;
  @override
  bool get canEdit => true;
  @override
  bool get canAuto => true;

  @override
  Future<WifiStatus> getStatus() async {
    return WifiStatus.fromJson(await _client.getWifiStatus());
  }

  @override
  Future<List<WifiScanEntry>> scan() async {
    final data = await _client.scanWifi();
    final raw = data['networks'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WifiScanEntry.fromJson)
        .toList();
  }

  @override
  Future<void> add(String ssid, String password, int priority) async {
    await _client.sendWifiCommand('wifi_add', {
      'ssid': ssid,
      'password': password,
      'priority': priority,
    });
  }

  @override
  Future<void> remove(int id) =>
      _client.sendWifiCommand('wifi_remove', {'id': id});

  @override
  Future<void> connect(int id) =>
      _client.sendWifiCommand('wifi_connect', {'id': id});

  @override
  Future<void> setPriority(int id, int priority) =>
      _client.sendWifiCommand('wifi_update', {'id': id, 'priority': priority});

  @override
  Future<void> setEnabled(int id, bool enabled) => _client.sendWifiCommand(
        'wifi_update',
        {'id': id, 'enabled': enabled},
      );

  @override
  Future<void> reorder(List<int> ids) =>
      _client.sendWifiCommand('wifi_reorder', {'ids': ids});

  @override
  Future<void> setAuto() => _client.sendWifiCommand('wifi_auto');
}

class SerialWifiTransport implements WifiTransport {
  final SerialService _serial;

  SerialWifiTransport(this._serial);

  @override
  bool get canScan => true;
  @override
  bool get canAdd => true;
  @override
  bool get canEdit => true;
  @override
  bool get canAuto => true;

  Future<Map<String, dynamic>> _request(
    String command,
    bool Function(Map<String, dynamic>) matches, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription<Map<String, dynamic>> sub;
    sub = _serial.responses.listen((message) {
      if (!completer.isCompleted && matches(message)) {
        completer.complete(message);
      }
    });
    _serial.sendCommand(command);
    try {
      return await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  @override
  Future<WifiStatus> getStatus() async {
    final response = await _request(
      'wifi_list',
      (m) => m['type'] == 'wifi_list' || m['type'] == 'error',
    );
    if (response['type'] == 'error') {
      throw StateError(response['error']?.toString() ?? 'wifi_list_failed');
    }
    return WifiStatus.fromJson(_payload(response));
  }

  @override
  Future<List<WifiScanEntry>> scan() async {
    final response = await _request(
      'wifi_scan',
      (m) => m['type'] == 'wifi_scan' || m['type'] == 'error',
      timeout: const Duration(seconds: 20),
    );
    if (response['type'] == 'error') {
      throw StateError(response['error']?.toString() ?? 'wifi_scan_failed');
    }
    final raw = _payload(response)['networks'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WifiScanEntry.fromJson)
        .toList();
  }

  Future<void> _ack(String command, String expectedCommand) async {
    final response = await _request(
      command,
      (m) =>
          (m['type'] == 'ack' && m['command'] == expectedCommand) ||
          m['type'] == 'error',
    );
    if (response['type'] == 'error') {
      throw StateError(response['error']?.toString() ?? 'failed');
    }
  }

  @override
  Future<void> add(String ssid, String password, int priority) async {
    final s = base64Encode(utf8.encode(ssid));
    final p = base64Encode(utf8.encode(password));
    await _ack('wifi_add_b64:$s:$p:$priority', 'wifi_add');
  }

  @override
  Future<void> remove(int id) => _ack('wifi_remove:$id', 'wifi_remove');

  @override
  Future<void> connect(int id) => _ack('wifi_connect:$id', 'wifi_connect');

  @override
  Future<void> setPriority(int id, int priority) =>
      _ack('wifi_priority:$id:$priority', 'wifi_priority');

  @override
  Future<void> setEnabled(int id, bool enabled) => _ack(
        'wifi_enable:$id:${enabled ? 1 : 0}',
        'wifi_enable',
      );

  @override
  Future<void> reorder(List<int> ids) async {
    for (var i = 0; i < ids.length; i++) {
      await setPriority(ids[i], i + 1);
    }
  }

  @override
  Future<void> setAuto() => _ack('wifi_auto', 'wifi_auto');
}

/// Remote transport: the server asks the device for its saved networks over
/// MQTT and performs a two-phase switch. Only existing profiles can be
/// selected; adding/scanning is intentionally disabled remotely.
class ServerWifiTransport implements WifiTransport {
  final ApiClient _api;
  final String _deviceId;

  ServerWifiTransport(this._api, this._deviceId);

  @override
  bool get canScan => false;
  @override
  bool get canAdd => false;
  @override
  bool get canEdit => false;
  @override
  bool get canAuto => false;

  @override
  Future<WifiStatus> getStatus() async {
    return WifiStatus.fromJson(await _api.getRemoteWifi(_deviceId));
  }

  @override
  Future<List<WifiScanEntry>> scan() =>
      throw UnsupportedError('scan requires local access');

  @override
  Future<void> add(String ssid, String password, int priority) =>
      throw UnsupportedError('add requires local access');

  @override
  Future<void> remove(int id) =>
      throw UnsupportedError('remove requires local access');

  @override
  Future<void> connect(int id) async {
    final prepared = await _api.prepareWifi(_deviceId, id);
    final requestId = prepared['request_id']?.toString();
    if (requestId == null || requestId.isEmpty) {
      throw StateError('prepare_failed');
    }
    await _api.commitWifi(_deviceId, requestId);
  }

  @override
  Future<void> setPriority(int id, int priority) =>
      throw UnsupportedError('priority requires local access');

  @override
  Future<void> setEnabled(int id, bool enabled) =>
      throw UnsupportedError('enable requires local access');

  @override
  Future<void> reorder(List<int> ids) =>
      throw UnsupportedError('reorder requires local access');

  @override
  Future<void> setAuto() =>
      throw UnsupportedError('auto requires local access');
}
