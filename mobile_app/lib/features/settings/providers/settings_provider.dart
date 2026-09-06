import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/connection_mode.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;

  static const String _defaultApiUrl = 'https://spe4naz.online';
  static const String _defaultMqttBroker = 'spe4naz.online';
  static const int _defaultMqttPort = 9001;

  static const String _legacyMqttBroker = 'localhost';
  static const int _legacyMqttPort = 1883;

  String _apiUrl = _defaultApiUrl;
  String _mqttBroker = _defaultMqttBroker;
  int _mqttPort = _defaultMqttPort;
  bool _darkMode = false;
  String _language = 'ru';
  int _accentColorIndex = 0;
  String? _backgroundImagePath;
  double _backgroundOpacity = 0.3;
  ConnectionMode _connectionMode = ConnectionMode.auto;

  String get apiUrl => _apiUrl;
  String get mqttBroker => _mqttBroker;
  int get mqttPort => _mqttPort;
  bool get darkMode => _darkMode;
  String get language => _language;
  int get accentColorIndex => _accentColorIndex;
  String? get backgroundImagePath => _backgroundImagePath;
  double get backgroundOpacity => _backgroundOpacity;
  ConnectionMode get connectionMode => _connectionMode;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final storedApiUrl = _prefs.getString('api_url');
    _apiUrl = _resolveApiUrl(storedApiUrl);

    final storedMqttBroker = _prefs.getString('mqtt_broker');
    _mqttBroker = (storedMqttBroker == null || storedMqttBroker == _legacyMqttBroker)
        ? _defaultMqttBroker
        : storedMqttBroker;

    final storedMqttPort = _prefs.getInt('mqtt_port');
    _mqttPort = (storedMqttPort == null || storedMqttPort == _legacyMqttPort)
        ? _defaultMqttPort
        : storedMqttPort;

    _darkMode = _prefs.getBool('dark_mode') ?? false;
    _language = _prefs.getString('language') ?? 'ru';
    _accentColorIndex = _prefs.getInt('accent_color_index') ?? 0;
    _backgroundImagePath = _prefs.getString('background_image_path');
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
