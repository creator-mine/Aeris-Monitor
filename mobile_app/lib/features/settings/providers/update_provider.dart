import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/app_update_service.dart';

enum UpdateCheckState { idle, checking, upToDate, updateAvailable, failed }

/// Tracks the app's own updates, published as GitHub Releases.
///
/// The automatic check runs at most once per [autoCheckInterval] and only when
/// the user left the "Проверять обновления" switch on.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider({AppUpdateService? service})
      : _service = service ?? AppUpdateService();

  static const Duration autoCheckInterval = Duration(hours: 4);
  static const String autoCheckKey = 'auto_check_updates';
  static const String lastCheckKey = 'update_last_check';

  final AppUpdateService _service;
  SharedPreferences? _prefs;

  bool _autoCheck = true;
  DateTime? _lastCheckAt;
  AppRelease? _available;
  UpdateCheckState _state = UpdateCheckState.idle;
  String? _error;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _inFlight;

  /// False until [init] has read the stored preferences. Auto checks stay off
  /// while uninitialized, which also keeps widget tests offline.
  bool get initialized => _initialized;

  bool get autoCheck => _autoCheck;
  DateTime? get lastCheckAt => _lastCheckAt;
  AppRelease? get available => _available;
  String? get availableVersion => _available?.version;
  UpdateCheckState get state => _state;
  String? get error => _error;
  bool get checking => _state == UpdateCheckState.checking;

  /// True when an automatic check is enabled and the last one is old enough.
  bool get autoCheckDue {
    if (!_autoCheck) return false;
    final last = _lastCheckAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= autoCheckInterval;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _autoCheck = _prefs?.getBool(autoCheckKey) ?? true;
    final storedMs = _prefs?.getInt(lastCheckKey);
    _lastCheckAt =
        storedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(storedMs);
    _initialized = true;
    _notify();
  }

  Future<void> setAutoCheck(bool value) async {
    _autoCheck = value;
    await _prefs?.setBool(autoCheckKey, value);
    _notify();
  }

  /// Silent check used on startup and by the periodic timer. Failures are
  /// swallowed: a missing network must not disturb the user.
  Future<void> maybeAutoCheck() async {
    if (!_initialized || !autoCheckDue || checking) return;
    await checkNow();
  }

  /// Manual or automatic check. Never throws: the result is exposed through
  /// [state], [available] and [error].
  Future<void> checkNow() async {
    final pending = _inFlight;
    if (pending != null) return pending;
    final future = _runCheck();
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _runCheck() async {
    _state = UpdateCheckState.checking;
    _error = null;
    _notify();

    try {
      final release = await _service.latestRelease();
      _lastCheckAt = DateTime.now();
      await _persistLastCheck();
      if (_service.isNewer(release)) {
        _available = release;
        _state = UpdateCheckState.updateAvailable;
      } else {
        _available = null;
        _state = UpdateCheckState.upToDate;
      }
    } on AppUpdateException catch (e) {
      _error = e.message;
      _state = UpdateCheckState.failed;
      _lastCheckAt = DateTime.now();
      await _persistLastCheck();
    } catch (e) {
      _error = 'Не удалось проверить обновления: $e';
      _state = UpdateCheckState.failed;
      _lastCheckAt = DateTime.now();
      await _persistLastCheck();
    }
    _notify();
  }

  Future<void> _persistLastCheck() async {
    final last = _lastCheckAt;
    if (last == null) return;
    await _prefs?.setInt(lastCheckKey, last.millisecondsSinceEpoch);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
