import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _defaultApiUrl = 'https://spe4naz.online';

/// Entry point for the foreground-task isolate.
@pragma('vm:entry-point')
void backgroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(AerisBackgroundTaskHandler());
}

/// Keeps a live SSE connection to the Aeris server while the app is in the
/// background and raises a system notification whenever a smart-home rule
/// fires (`event: rule`).
class AerisBackgroundTaskHandler extends TaskHandler {
  HttpClient? _http;
  bool _running = false;
  FlutterLocalNotificationsPlugin? _notifications;
  String _apiUrl = _defaultApiUrl;
  String _token = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('api_url') ?? _defaultApiUrl;
      _apiUrl = stored.trim().replaceAll(RegExp(r'/+$'), '');
      if (_apiUrl.isEmpty) _apiUrl = _defaultApiUrl;
      _token = prefs.getString('signaling_token') ?? '';
    } catch (_) {}

    _notifications = FlutterLocalNotificationsPlugin();
    try {
      await _notifications!.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {}

    _running = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_running) {
      try {
        await _listen();
      } catch (_) {}
      if (!_running) break;
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  Future<void> _listen() async {
    final client = HttpClient();
    _http = client;
    try {
      final req = await client.getUrl(Uri.parse('$_apiUrl/api/v1/stream'));
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (_token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      final res = await req.close();

      String? event;
      final data = StringBuffer();
      await for (final line
          in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!_running) break;
        if (line.isEmpty) {
          if (event == 'rule' && data.isNotEmpty) {
            _onRule(data.toString());
          }
          event = null;
          data.clear();
          continue;
        }
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  void _onRule(String raw) {
    var body = 'Сработало правило умного дома';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rule = map['rule'];
      if (rule is Map) {
        final name = rule['name'] ?? rule['sensor_type'];
        if (name != null && name.toString().trim().isNotEmpty) {
          body = 'Сработало правило: $name';
        }
      }
    } catch (_) {}
    unawaited(_show('Aeris Monitor', body));
  }

  Future<void> _show(String title, String body) async {
    final plugin = _notifications;
    if (plugin == null) return;
    try {
      await plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'aeris_alerts',
            'Оповещения Aeris',
            channelDescription: 'События устройств и умного дома',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Aeris Monitor',
      notificationText: 'Слежу за устройствами…',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _running = false;
    _http?.close(force: true);
  }
}

/// Starts the Android foreground monitor. No-op on other platforms.
Future<void> startBackgroundMonitor() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'aeris_service',
      channelName: 'Aeris Monitor',
      channelDescription: 'Фоновый мониторинг устройств',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  try {
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  } catch (_) {}

  try {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Aeris Monitor',
        notificationText: 'Слежу за устройствами…',
        callback: backgroundStartCallback,
      );
    }
  } catch (_) {}
}
