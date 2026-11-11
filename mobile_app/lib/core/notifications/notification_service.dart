import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

/// Cross-platform local notifications.
///
/// - Android: system notifications via flutter_local_notifications.
/// - Windows / Linux / macOS: local_notifier (desktop).
/// - Web: disabled.
class NotificationService {
  static bool _ready = false;
  static FlutterLocalNotificationsPlugin? _android;

  static Future<void> init() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final plugin = FlutterLocalNotificationsPlugin();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await plugin.initialize(settings: settings);
      _android = plugin;
      _ready = true;
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await LocalNotifier.instance.setup(appName: 'Aeris Monitor');
      _ready = true;
    }
  }

  static bool get available => _ready;

  static Future<void> show(String title, String body, {int id = 0}) async {
    if (!_ready) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _android?.show(
        id: id,
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
      return;
    }

    LocalNotification(title: title, body: body).show();
  }
}
