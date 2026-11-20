import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/secret_store.dart';
import 'background_prefs.dart';

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
  String _username = 'app';
  String _password = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('api_url') ?? _defaultApiUrl;
      _apiUrl = stored.trim().replaceAll(RegExp(r'/+$'), '');
      if (_apiUrl.isEmpty) _apiUrl = _defaultApiUrl;
      _username = prefs.getString('mqtt_username') ?? 'app';
      // The password lives in the OS keystore since 1.3.6; the pref is only a
      // legacy fallback for installs that have not migrated yet.
      _password = prefs.getString(mqttPasswordSecretKey) ?? '';
      try {
        final stored =
            await const FlutterSecureStorage().read(key: mqttPasswordSecretKey);
        if (stored != null) _password = stored;
      } catch (_) {
        // Secure storage is unavailable in this isolate: keep the fallback.
      }
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
      if (_password.isNotEmpty) {
        final raw = base64Encode(utf8.encode('$_username:$_password'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Basic $raw');
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
    // Intentionally empty: this used to call updateService() every minute,
    // which re-posts the ongoing notification and made it pop up again and
    // again. The notification only needs to be shown once, at start.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _running = false;
    _http?.close(force: true);
  }
}

/// Starts the Android foreground monitor. No-op on other platforms.
///
/// [force] restarts an already running service (needed after the API URL or
/// the credentials change, because the isolate reads them once at start). Without
/// it an existing service is left untouched: restarting it would cancel and
/// re-post the notification on every app launch.
Future<void> startBackgroundMonitor({bool force = false}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(backgroundMonitorPrefKey) ?? true)) return;

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      // A new channel id is required: Android keeps the settings of an
      // existing channel forever, so an old high-importance channel would
      // keep peeking even after the code changes.
      channelId: 'aeris_service_v2',
      channelName: 'Aeris Monitor',
      channelDescription: 'Фоновый мониторинг устройств',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // No periodic event: the handler keeps its own SSE loop, and a repeat
      // action would only re-post the notification.
      eventAction: ForegroundTaskEventAction.nothing(),
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
      if (force) await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Aeris Monitor',
      notificationText: 'Слежу за устройствами…',
      callback: backgroundStartCallback,
    );
  } catch (_) {}
}

/// Stops the foreground monitor and removes its notification.
Future<void> stopBackgroundMonitor() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  } catch (_) {}
}
