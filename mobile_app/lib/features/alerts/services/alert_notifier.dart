import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/notifications/notification_service.dart';

/// Local notifications are available on every platform except web.
bool localNotificationsAvailable() => !kIsWeb;

/// Throttle identical notifications so a continuous alarm state does not
/// repeatedly spam the OS notification center.
class AlertNotifier {
  static final Map<String, DateTime> _lastSent = {};
  static const Duration _cooldown = Duration(minutes: 10);

  /// Shows a notification for an arbitrary title/body, throttled by title.
  /// No-op on web.
  static void notify(String title, String body) {
    if (!localNotificationsAvailable()) return;

    final key = 'custom:$title';
    final last = _lastSent[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _cooldown) return;

    _lastSent[key] = now;
    unawaited(NotificationService.show(title, body));
  }
}
