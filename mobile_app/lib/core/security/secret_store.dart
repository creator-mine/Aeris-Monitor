import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SharedPreferences key that used to hold the MQTT password in clear text.
/// It is now only used as a migration source / emergency fallback.
const String mqttPasswordSecretKey = 'mqtt_password';

/// Key/value storage for secrets such as the MQTT password.
///
/// Implementations must keep values out of [SharedPreferences]: the OS
/// keystore (Android Keystore, Windows DPAPI/Credential Manager, WebCrypto on
/// web) is used by [SecureSecretStore].
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// OS-backed secret storage.
///
/// Unit tests and platforms without the plugin fall back to an in-memory map so
/// the app still starts; in that case the value lives only for the session.
class SecureSecretStore implements SecretStore {
  SecureSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _session = {};
  bool _pluginUnavailable = false;

  @override
  Future<String?> read(String key) async {
    if (_pluginUnavailable) return _session[key];
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      _markUnavailable();
      return _session[key];
    } on PlatformException catch (e) {
      // A locked or corrupted keystore must not block app startup; the user
      // will be asked for the password again.
      debugPrint('Secure storage read failed for "$key": ${e.code}');
      return _session[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (_pluginUnavailable) {
      _session[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
      _session.remove(key);
    } on MissingPluginException {
      _markUnavailable();
      _session[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _session.remove(key);
    if (_pluginUnavailable) return;
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      _markUnavailable();
    } on PlatformException catch (e) {
      debugPrint('Secure storage delete failed for "$key": ${e.code}');
    }
  }

  void _markUnavailable() {
    if (_pluginUnavailable) return;
    _pluginUnavailable = true;
    debugPrint(
      'flutter_secure_storage is unavailable; secrets are kept in memory only',
    );
  }
}
