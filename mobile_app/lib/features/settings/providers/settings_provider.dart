import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/connection_mode.dart';
import '../../../core/config/log_mode.dart';
import '../../../core/config/app_config.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;

  static const String _defaultApiUrl = 'https://spe4naz.online';
  static const String _defaultMqttBroker = 'spe4naz.online';
  static const int _defaultMqttPort = kIsWeb ? 9002 : 8883;

  static const String _legacyMqttBroker = 'localhost';
  static const int _legacyMqttPort = 1883;
  static const int _legacyWsPort = 9001;

  static String get _defaultMqttUsername => AppConfig.mqttUsername;
  static String get _defaultMqttPassword => AppConfig.mqttPassword;

  String _apiUrl = _defaultApiUrl;
  String _otaUrl = '';
  String _mqttBroker = _defaultMqttBroker;
  int _mqttPort = _defaultMqttPort;
  String _mqttUsername = AppConfig.mqttUsername;
  String _mqttPassword = AppConfig.mqttPassword;
  String _signalingToken = AppConfig.signalingToken;
  bool _darkMode = false;
  String _language = 'ru';
  LogMode _logMode = LogMode.standard;
  int _accentColorIndex = 0;
  String? _backgroundImagePath;
  Uint8List? _backgroundImageBytes;
  double _backgroundOpacity = 0.3;
  ConnectionMode _connectionMode = ConnectionMode.auto;

  String get apiUrl => _apiUrl;
  String get otaUrl => _otaUrl;
  String get mqttBroker => _mqttBroker;
  int get mqttPort => _mqttPort;
  String get mqttUsername => _mqttUsername;
  String get mqttPassword => _mqttPassword;
  String get signalingToken => _signalingToken;
  bool get darkMode => _darkMode;
  String get language => _language;
  LogMode get logMode => _logMode;
  int get accentColorIndex => _accentColorIndex;
  String? get backgroundImagePath => _backgroundImagePath;
  Uint8List? get backgroundImageBytes => _backgroundImageBytes;
  double get backgroundOpacity => _backgroundOpacity;
  ConnectionMode get connectionMode => _connectionMode;

  /// OTA/firmware host actually used: explicit value if set, else the API URL
  /// (the self-hosted stack serves /fw from the same nginx).
  String get effectiveOtaUrl {
    final v = _otaUrl.trim();
    return v.isEmpty ? _apiUrl : v;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final storedApiUrl = _prefs.getString('api_url');
    _apiUrl = _resolveApiUrl(storedApiUrl);

    _otaUrl = _prefs.getString('ota_url')?.trim() ?? '';

    final storedMqttBroker = _prefs.getString('mqtt_broker');
    _mqttBroker = (storedMqttBroker == null || storedMqttBroker == _legacyMqttBroker)
        ? _defaultMqttBroker
        : storedMqttBroker;

    final storedMqttPort = _prefs.getInt('mqtt_port');
    _mqttPort = (storedMqttPort == null ||
            storedMqttPort == _legacyMqttPort ||
            storedMqttPort == _legacyWsPort)
        ? _defaultMqttPort
        : storedMqttPort;

    _mqttUsername = _prefs.getString('mqtt_username') ?? _defaultMqttUsername;
    _mqttPassword = _prefs.getString('mqtt_password') ?? _defaultMqttPassword;
    _signalingToken = _prefs.getString('signaling_token') ?? AppConfig.signalingToken;

    _darkMode = _prefs.getBool('dark_mode') ?? false;
    _language = _prefs.getString('language') ?? 'ru';
    _logMode = LogMode.values.firstWhere(
      (m) => m.name == _prefs.getString('log_mode'),
      orElse: () => LogMode.standard,
    );
    _accentColorIndex = _prefs.getInt('accent_color_index') ?? 0;
    _backgroundImagePath = _prefs.getString('background_image_path');
    final storedBackgroundB64 = _prefs.getString('background_image_bytes');
    if (storedBackgroundB64 != null && storedBackgroundB64.isNotEmpty) {
      try {
        _backgroundImageBytes = base64Decode(storedBackgroundB64);
      } catch (_) {
        _backgroundImageBytes = null;
      }
    }
    _backgroundOpacity = _prefs.getDouble('background_opacity') ?? 0.3;

    final storedMode = _prefs.getString('connection_mode');
    _connectionMode = ConnectionMode.values.firstWhere(
      (m) => m.name == storedMode,
      orElse: () => ConnectionMode.auto,
    );
    notifyListeners();
  }

  /// Normalizes a stored server URL and maps any localhost/legacy value to
  /// the production default so stale builds or leftover dev settings are
  /// upgraded automatically.
  static String _resolveApiUrl(String? stored) {
    if (stored == null) return _defaultApiUrl;
    var url = stored.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return _defaultApiUrl;
    final lower = url.toLowerCase();
    if (lower.contains('localhost') || lower.contains('127.0.0.1')) {
      return _defaultApiUrl;
    }
    return url;
  }

  Future<void> setApiUrl(String url) async {
    _apiUrl = url;
    await _prefs.setString('api_url', url);
    notifyListeners();
  }

  Future<void> setOtaUrl(String url) async {
    _otaUrl = url.trim();
    await _prefs.setString('ota_url', _otaUrl);
    notifyListeners();
  }

  Future<void> setMqttBroker(String broker) async {
    _mqttBroker = broker;
    await _prefs.setString('mqtt_broker', broker);
    notifyListeners();
  }

  Future<void> setMqttPort(int port) async {
    _mqttPort = port;
    await _prefs.setInt('mqtt_port', port);
    notifyListeners();
  }

  Future<void> setMqttUsername(String username) async {
    _mqttUsername = username;
    await _prefs.setString('mqtt_username', username);
    notifyListeners();
  }

  Future<void> setMqttPassword(String password) async {
    _mqttPassword = password;
    await _prefs.setString('mqtt_password', password);
    notifyListeners();
  }

  Future<void> setSignalingToken(String token) async {
    _signalingToken = token;
    await _prefs.setString('signaling_token', token);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _prefs.setBool('dark_mode', value);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    await _prefs.setString('language', lang);
    notifyListeners();
  }

  Future<void> setLogMode(LogMode mode) async {
    _logMode = mode;
    await _prefs.setString('log_mode', mode.name);
    notifyListeners();
  }

  Future<void> setAccentColorIndex(int index) async {
    _accentColorIndex = index;
    await _prefs.setInt('accent_color_index', index);
    notifyListeners();
  }

  Future<void> setBackgroundImagePath(String? path) async {
    _backgroundImagePath = path;
    if (path != null) {
      await _prefs.setString('background_image_path', path);
    } else {
      await _prefs.remove('background_image_path');
    }
    notifyListeners();
  }

  /// Web build: background is stored as in-memory bytes (no local FS path).
  Future<void> setBackgroundImageBytes(Uint8List bytes) async {
    _backgroundImageBytes = bytes;
    await _prefs.setString('background_image_bytes', base64Encode(bytes));
    notifyListeners();
  }

  /// Clears the background on every platform (path on desktop, bytes on web).
  Future<void> clearBackgroundImage() async {
    _backgroundImagePath = null;
    _backgroundImageBytes = null;
    await _prefs.remove('background_image_path');
    await _prefs.remove('background_image_bytes');
    notifyListeners();
  }

  Future<void> setBackgroundOpacity(double opacity) async {
    _backgroundOpacity = opacity;
    await _prefs.setDouble('background_opacity', opacity);
    notifyListeners();
  }

  Future<void> setConnectionMode(ConnectionMode mode) async {
    _connectionMode = mode;
    await _prefs.setString('connection_mode', mode.name);
    notifyListeners();
  }
}
